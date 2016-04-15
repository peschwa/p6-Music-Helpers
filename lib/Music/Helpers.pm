use v6.c;

=begin pod

=head1 NAME

Music::Helpers - Abstractions for handling musical content

=head1 SYNOPSIS

    use Music::Helpers;

    my $mode = Mode.new(:root(C), :mode('major'))

    # prints 'C4 E4 G4 ==> C maj (inversion: 0)'
    say $mode.tonic.Str;

    # prints 'F4 A4 C5 ==> F maj (inversion: 0)'
    say $mode.next-chord($mode.tonic, intervals => [P4]).Str;

=head1 DESCRIPTION

This module provides a few OO abstraction for handling musical content.
Explicitly these are the classes C<Mode>, C<Chord> and C<Note> as well as Enums
C<NoteName> and C<Interval>. As anyone with even passing musical knowledge
knows, C<Mode>s and C<Chord>s consists of C<Note>s with one of those being the
root and the others having a specific half-step distance from this root. As the
main purpose for this module is utilizing these classes over MIDI (via
[Audio::PortMIDI](https://github.com/jonathanstowe/Audio-PortMIDI/)),
non-standard tunings will have to be handled by the instruments that play these
notes.

A C<Mode> knows, which natural triads it contains, and memoizes the C<Note>s
and C<Chord>s on each step of the scale for probably more octaves than
necessary. (That is, 10 octaves, from C-1 to C9, MIDI values 0 to 120.)
Further, a C<Chord> knows via a set of Roles applied at construction time,
which kind of alterations on it are feasible. E.g:

    my $mode  = Mode.new(:root(F), :mode<major>);
    my $fmaj  = $mode.tonic;
    my $fdom7 = $fmaj.dom7;
    # prints 'F4 G4 C5 => F4 sus2 (inversion: 0)'
    say $fsus2.Str;

    my $mode = Mode.new(:root(F), :mode<minor>);
    my $fmin = $mode.tonic;
    # dies, "Method 'dom7' not found for invocant of class 'Music::Helpers::Chord+{Music::Helpers::min}'
    my $fdom7 = $fmin.dom7;

Although I do readily admit that by far not all possible alterations and
augmentations are currently implemented. The ones available are C<.sus2> and
C<.sus4> for minor and major chords, and C<.dom7> for major chords. Patches
welcome. :)

Further, positive and negative inversions are supported via the method
C<.invert>:

    # prints 'C5 F5 A5 ==> F5 maj (inversion: 2)'
    say $fmaj.invert(2).Str;

    # prints 'C4 F4 A4 ==> F4 maj (inversion: 2)'
    say $fmaj.invert(-1).Str;

Finally, a C<Note> knows how to build a C<Audio::PortMIDI::Event> that can be
sent via a C<Audio::PortMIDI::Stream>, and a C<Chord> knows to ask the C<Note>s
it consists of for these Events:

    # prints a whole lot, not replicated for brevity
    say $fmaj.OnEvents;

Note that this documentation is a work in progress. The file bin/example.pl6 in
this repository might be of interest.

=end pod

use Audio::PortMIDI;

unit package Music::Helpers;

enum NoteName is export <C Cs D Ds E F Fs G Gs A As B Bs>;
enum Interval is export <P1 m2 M2 m3 M3 P4 TT P5 m6 M6 m7 M7 P8>;

class Note is export {
    has Int $.midi is required;
    has $.freq;
    has $.vel = 95;

    method is-interval(Note:D: Note:D $rhs, Interval $int --> Bool) {
        if self < $rhs {
            abs($rhs.name.value - self.name.value) == $int
        }
        else {
            abs(self.name.value - $rhs.name.value) == $int
        }
    }

    multi infix:<==>(Note:D $lhs, Note:D $rhs) is export {
        $lhs.name == $rhs.name
    }

    multi infix:<===>(Note:D $lhs, Note:D $rhs) is export {
        $lhs == $rhs && $lhs.octave == $rhs.octave
    }

    multi infix:<->(Note:D $lhs, Note:D $rhs --> Interval) is export {
        my $oct = ($lhs.midi - $rhs.midi) div 12;
        my $int = Interval( ($lhs.midi - $rhs.midi) % 12 );
        $int but role { method octaves { $oct } };
    }

    multi infix:<+>(Note:D $note, Int $interval --> Note) is export {
        Note.new(midi => $note.midi + $interval)
    }

    multi infix:<->(Note:D $note, Int $interval --> Note) is export {
        &infix:<+>($note, -$interval)
    }

    multi infix:<->(Int $interval, Note:D $note --> Note) is export {
        &infix:<+>($note, -$interval)
    }

    multi infix:<+>(Int $interval, Note:D $note --> Note) is export {
        &infix:<+>($note, $interval)
    }

    multi infix:«>»(Note:D $lhs, Note:D $rhs --> Bool) is export {
        $lhs.midi < $rhs.midi
    }

    multi infix:«<»(Note:D $lhs, Note:D $rhs --> Bool) is export {
        $lhs.midi < $rhs.midi
    }

    method Numeric {
        $.midi
    }

    method octave {
        $.midi div 12
    }

    method OffEvent(Int $channel = 1) {
        Audio::PortMIDI::Event.new(event-type => NoteOff, data-one => $.midi, data-two => $.vel, timestamp => 0, :$channel);
    }
    method OnEvent(Int $channel = 1) {
        Audio::PortMIDI::Event.new(event-type => NoteOn, data-one => $.midi, data-two => $.vel, timestamp => 0, :$channel);
    }

    method name {
        NoteName($.midi % 12);
    }

    method Str {
        NoteName($.midi % 12).key ~ ($.midi div 12)
    }
}

import Note;
class Chord { ... };

role for-naming {
    # XXX this feels terrible
    method chord-type { self.HOW.roles(self).grep({ $_ ~~ for-naming && $_ !=== for-naming })[0].^shortname }
}
role sus-able is export {
    method sus2 {
        Chord.new(notes => [ self.normal.notes[0], self.normal.notes[0] + M2, self.normal.notes[2] ]).invert(self.inversion)
    }
    method sus4 {
        Chord.new(notes => [ self.normal.notes[0], self.normal.notes[0] + P4, self.normal.notes[2] ]).invert(self.inversion)
    }
}
role maj does sus-able does for-naming is export {
    method dom7 {
        Chord.new(notes => [ |self.normal.notes, self.normal.notes[2] + m3 ]).invert($.inversion)
    }
    method intervals-in-inversion {
        [[M3, m3], [m3, P4], [P4, m3]]
    }
}
role min does sus-able does for-naming is export {
    method intervals-in-inversion {
        [[m3, M3], [M3, P4], [P4, m3]]
    }
}
role dim does for-naming is export {
    method intervals-in-inversion {
        [[m3, m3], [m3, TT], [TT, m3]]
    }
}
role aug does for-naming is export {
    method intervals-in-inversion {
        [[M3, M3], [M3, M3], [M3, M3]]
    }
}
role maj6 does for-naming is export {
    method intervals-in-inversion {
        [[M3, m3, M2], [m3, M2, m3], [M2, m3, M3], [m3, M3, m3]]
    }
}
#`[[[[
    Something about these roles and applying them during BUILD is kind of shit.
    as in, intervals alone aren't enough to determine what chord we are, we also need the root
    to know from where to where to count and all.  so probably just sort by notename..?
]]]]
role min6 does for-naming is export {
    method intervals-in-inversion {
        [[m3, M3, M2], [M3, M2, m3], [M2, m3, m3], [m3, m3, M3]]
    }
}
role dom7 does for-naming is export {
    method TT-subst {
        my @notes = $.invert(-$.inversion).notes;
        my $third = @notes[3];
        my $seventh = @notes[1] - 12;
        my $root = $third - M3;
        my $fifth = $seventh - m3;
        Chord.new[notes => [ $root, $third, $fifth, $seventh ]].invert($.inversion);
    }
    method intervals-in-inversion {
        [[M3, m3, m3], [m3, m3, M2], [m3, M2, M3], [M2, M3, m3]]
    }
}
role maj7 does for-naming is export {
    method intervals-in-inversion {
        [[M3, m3, M3], [m3, M3, m2], [M3, m2, M3], [m2, M3, m3]]
    }
}
role min7 does for-naming is export {
    method intervals-in-inversion {
        [[m3, M3, m3], [M3, m3, M2], [m3, M2, m3], [M2, m3, M3]]
    }
}
role aug7 does for-naming is export {
    method intervals-in-inversion {
        [[M3, M3, M2], [M3, m2, M2], [m2, M2, M3], [M2, M3, M3]]
    }
}
role dim7 does for-naming is export {
    method intervals-in-inversion {
        [[m3, m3, m3], [m3, m3, m3], [m3, m3, m3], [m3, m3, m3]]
    }
}
role halfdim7 does for-naming is export {
    method intervals-in-inversion {
        [[m3, m3, M3], [m3, M3, M2], [M3, M2, m3], [M2, m3, m3]]
    }
}
role minmaj7 does for-naming is export {
    method intervals-in-inversion {
        [[m3, M3, M3], [M3, M3, m2], [M3, m2, m3], [m2, m3, M3]]
    }
}

role weird does for-naming is export { }

role sus2 does for-naming is export { }
role sus4 does for-naming is export { }

class Chord is export {
    has Note @.notes;
    has $.inversion;

    method normal(Chord:D: ) {
        self.invert(-$.inversion)
    }

    method root(Chord:D: ) {
        @.notes[(* - $.inversion) % *]
    }

    method third(Chord:D: ) {
        @.notes[($.inversion + 1) % self.notes]
    }

    method fifth(Chord:D: ) {
        @.notes[($.inversion + 2) % self.notes]
    }

    method invert(Chord:D: Int $degree is copy = 1) {
        my @new-notes = @.notes;
        my $inversion = $degree % @.notes;
        if $degree == 0 {
            self
        }
        elsif $degree < 0 {
            while $degree++ < 0 {
                my $tmp = @new-notes.pop - 12;
                @new-notes = $tmp, |@new-notes;
            }
        }
        elsif $degree > 0 {
            while $degree-- > 0 {
                my $tmp = @new-notes.shift + 12;
                @new-notes = |@new-notes, $tmp;
            }
        }
        Chord.new(notes => @new-notes.Slip, :inversion($inversion + $.inversion));
    }

    submethod BUILD(:@!notes, :$!inversion = 0) {
        @!notes = @!notes;
        $!inversion = $!inversion % +@!notes;

        my @intervals;
        loop (my $i = 1; $i < @!notes; ++$i) {
            @intervals.push: Interval((@!notes[$i] - @!notes[$i - 1]).value);
        }

        for maj, min, dim, aug, maj6, min6, dom7, maj7, min7, aug7, dim7, halfdim7, minmaj7 {
            if @intervals eqv $_.intervals-in-inversion[$!inversion] {
                self does $_;
                last
            }
        }

    }

    method OffEvents(Chord:D: Int $channel = 1) {
        @.notes>>.OffEvent($channel);
    }
    method OnEvents(Chord:D: Int $channel = 1) {
        @.notes>>.OnEvent($channel);
    }

    method Str(Chord:D: ) {
        my $name = @.notes>>.Str;

        $name ~= " ==> $.root $.chord-type";
        $name ~ " (inversion: $.inversion)";
    }
}

class Mode is export {

    #`{{{
        All of this might still become useful, but I don't see how right now...

        enum Positions < Ton subp domp Sub Dom tonp dim >;

        sub min ($t) { ($t, $t + 3, $t + 7) }
        sub min7 ($t) { ($t, $t + 3, $t + 7, $t + 10) }
        sub min7p ($t) { ($t, $t + 3, $t + 7, $t + 11) }
        sub maj ($t) { ($t, $t + 4, $t + 7) }
        sub maj7 ($t) { ($t, $t + 4, $t + 7, $t + 11) }
        sub maj7s ($t) { ($t, $t + 4, $t + 7, $t + 10) }
        sub dim ($t) { ($t, $t + 3, $t + 7) }

        my %chords = Ton,  [ &maj, &maj7  ],
                     subp, [ &min, &min7  ],
                     domp, [ &min, &min7  ],
                     Sub,  [ &maj, &maj7  ],
                     Dom,  [ &maj, &maj7s ],
                     tonp, [ &min, &min7  ],
                     dim,  [ &dim, &dim   ];

        my %progs = Ton,  (:{Ton => 3, subp => 6, domp => 4, Sub => 8, Dom => 6, tonp => 4, dim => 1}).BagHash,
                    subp, (:{Ton => 2, subp => 3, domp => 6, Sub => 5, Dom => 8, tonp => 2, dim => 1}).BagHash,
                    domp, (:{Ton => 5, subp => 2, domp => 2, Sub => 7, Dom => 8, tonp => 4, dim => 2}).BagHash,
                    Sub,  (:{Ton => 3, subp => 3, domp => 7, Sub => 2, Dom => 8, tonp => 4, dim => 2}).BagHash,
                    Dom,  (:{Ton => 8, subp => 4, domp => 3, Sub => 5, Dom => 4, tonp => 6, dim => 3}).BagHash,
                    tonp, (:{Ton => 3, subp => 6, domp => 4, Sub => 5, Dom => 3, tonp => 2, dim => 1}).BagHash,
                    dim,  (:{Ton => 8, subp => 4, domp => 3, Sub => 5, Dom => 6, tonp => 4, dim => 1}).BagHash;

    }}}

    my %modes = ionian      =>    [P1,M2,M3,P4,P5,M6,M7],
                dorian      =>    [P1,M2,m3,P4,P5,M6,m7],
                phrygian    =>    [P1,m2,m3,P4,P5,m6,m7],
                lydian      =>    [P1,M2,M3,TT,P5,M6,M7],
                mixolydian  =>    [P1,M2,M3,P4,P5,M6,m7],
                aeolian     =>    [P1,M2,m3,P4,P5,M6,m7],
                locrian     =>    [P1,m2,m3,P4,TT,m6,m7],
                major       =>    [P1,M2,M3,P4,P5,M6,M7],
                minor       =>    [P1,M2,m3,P4,P5,m6,m7];
                # pentatonic  =>    [P1,M2,M3,   P5,M6,  ];

    # subset ModeName of Str where * eq any %modes.keys;

    has $.mode is required;
    has NoteName $.root is required;
    has Note @!notes;
    has @.weights; # NYI, the multi-line commented part above might be useful...

    method modes {
        %modes;
    }

    submethod BUILD(:$!mode, NoteName :$!root, :@!weights) { }

    method tonic(Mode:D: :$octave = 4) {
        $.chords.grep({ $_.root == $.root-note && $_.root.octave == $octave })[0]
    }

    method root-note(Mode:D: :$octave = 4) {
        Note.new(:midi($!root + $octave * 12))
    }

    method next-chord(Mode:D: Chord $current, :@intervals = [ P1, P4, P5 ], :@octaves = [4]) {
        if @.weights { ... }
        else {
            my @next = self.chords.grep({
                $_.root.is-interval($current.root, any(@intervals)) && $current.root - $_.root <= M7
            });
            @next.pick;
        }
    }

    method notes() {
        if !@!notes.elems {
            for @(%modes{$.mode}) -> $mode-offset {
                for ^10 -> $oct-offset {
                    @!notes.append( Note.new(midi => ($mode-offset + $!root + (12 * $oct-offset))) );
                }
            }
            @!notes .= sort({ $^a.midi <=> $^b.midi });
        }
        @!notes
    }

    method octave(Int $oct = 4) {
        self.notes[($oct * %modes{$.mode})..($oct * %modes{$.mode} + %modes{$.mode})]
    }

    my @chords;
    method chords(Mode:D:) {
        if !@chords {
            my @all-notes = |$.notes;
            loop (my int $i = 0; $i < @all-notes - 4; ++$i) {
                my @notes = @all-notes[$i], @all-notes[$i + 2], @all-notes[$i + 4];
                @chords.push: my $chrd = Chord.new: :@notes
            }
        }
        @chords
    }
}

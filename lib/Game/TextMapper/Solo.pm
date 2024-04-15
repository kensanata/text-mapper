# Copyright (C) 2024  Alex Schroeder <alex@gnu.org>
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option) any
# later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.

=encoding utf8

=head1 NAME

Game::TextMapper::Solo - generate a map generated step by step

=head1 SYNOPSIS

    use Modern::Perl;
    use Game::TextMapper::Solo;
    my $map = Game::TextMapper::Solo->new->generate_map();
    print $map;

=head1 DESCRIPTION

This starts the map and generates all the details directly, for each step,
without knowledge of the rest of the map. The tricky part is to generate
features such that no terrible geographical problems arise.

=cut

package Game::TextMapper::Solo;
use Game::TextMapper::Log;
use Modern::Perl '2018';
use List::Util qw(shuffle any);
use Mojo::Base -base;

my $log = Game::TextMapper::Log->get;

=head1 ATTRIBUTES

=head2 rows

The height of the map, defaults to 10.

    use Modern::Perl;
    use Game::TextMapper::Solo;
    my $map = Game::TextMapper::Solo->new(rows => 20)
        ->generate_map;
    print $map;

=head2 cols

The width of the map, defaults to 20.

    use Modern::Perl;
    use Game::TextMapper::Solo;
    my $map = Game::TextMapper::Solo->new(cols => 30)
        ->generate_map;
    print $map;

=cut

has 'rows' => 15;
has 'cols' => 20;
has 'altitudes' => sub{[]}; # these are the altitudes of each hex, a number between 0 (deep ocean) and 10 (ice)
has 'tiles' => sub{[]}; # these are the tiles on the map, an array of arrays of strings
has 'flows' => sub{[]}; # these are the water flow directions on the map, an array of coordinates
has 'rivers' => sub{[]}; # for rendering, the flows are turned into rivers, an array of arrays of coordinates
has 'trails' => sub{[]};
has 'slope'; # preferred river direction
has 'loglevel';

my @tiles = qw(plain rough swamp desert forest hills green-hills forest-hill mountains mountain volcano ice water coastal ocean);
my @no_sources = qw(desert volcano water coastal ocean);
my @settlements = qw(house ruin ruined-tower ruined-castle tower castle cave);

=head1 METHODS

=head2 generate_map

This method takes no arguments. Set the properties of the map using the
attributes.

=cut

sub generate_map {
  my ($self) = @_;
  $log->level($self->loglevel) if $self->loglevel;
  $self->slope(int(rand(6)));
  $self->random_walk();
  # my $walks = $self->random_walk();
  # debug random walks
  # my @walks = @$walks;
  # @walks = @walks[0 .. 10];
  # $self->trails(\@walks);
  return $self->to_text();
}

sub random_walk {
  my ($self) = @_;
  my %seen;
  my $tile_count = 0;
  my $path_length = 1;
  my $max_tiles = $self->rows * $self->cols;
  my $start = $self->rows / 2 * $self->cols + $self->cols / 2;
  $self->altitudes->[$start] = 5;
  my @neighbours = $self->neighbours($start);
  # initial river setup: roll a d6 four destination
  $self->flows->[$start] = $neighbours[int(rand(6))];
  # roll a d6 for source, skip if same as destination
  my $source = $neighbours[int(rand(6))];
  $self->flows->[$source] = $start unless $source == $self->flows->[$start];
  # initial setup: roll for starting region and the surrounding hexes
  for my $to ($start, @neighbours) {
    $seen{$to} = 1;
    $self->random_tile($start, $to);
    push(@{$self->tiles->[$to]}, qq("$tile_count/$to"));
    $tile_count++;
  }
  # remember those walks for debugging (assign to trails, for example)
  my $walks = [];
  # while there are still undiscovered hexes
  while ($tile_count < $max_tiles) {
    # create an expedition of length l
    my $from = $start;
    my $to = $start;
    my $walk = [];
    for (my $i = 0; $i < $path_length; $i++) {
      push(@$walk, $to);
      if (not $seen{$to}) {
        $seen{$to} = 1;
        $self->random_tile($from, $to);
        push(@{$self->tiles->[$to]}, qq("$tile_count/$to"));
        $tile_count++;
      }
      $from = $to;
      $to = $self->neighbour($from, \%seen);
    }
    $path_length++;
    push(@$walks, $walk);
    # last if @$walks > 10;
  }
  return $walks;
}

sub random_tile {
  my ($self, $from, $to) = @_;
  my $roll = roll_2d6();
  my $altitude = $self->adjust_altitude($roll, $from, $to);
  $self->add_flow($to);
  my $tile;
  if    ($altitude == 0) { $tile = 'ocean' }
  elsif ($altitude == 1) { $tile = 'coastal' }
  elsif ($altitude == 2) { $tile = 'desert' }
  elsif ($altitude == 3) { $tile = 'desert' }
  elsif ($altitude == 4) { $tile = 'desert' }
  elsif ($altitude == 5) { $tile = 'desert' }
  elsif ($altitude == 6) { $tile = 'desert' }
  elsif ($altitude == 7) { $tile = 'hills' }
  elsif ($altitude == 8) { $tile = 'mountains' }
  elsif ($altitude == 9) { $tile = special() ? 'volcano' : 'mountain' }
  else                   { $tile = 'ice' }
  push(@{$self->tiles->[$to]}, $tile);
  push(@{$self->tiles->[$to]}, qq("+$altitude"));
}

sub adjust_altitude {
  my ($self, $roll, $from, $to) = @_;
  my $altitude = $self->altitudes->[$from];
  my $max = 10;
  # if we're following a river, the altitude rarely goes up
  for ($self->neighbours($to)) {
    if (defined $self->flows->[$_]
        and $self->flows->[$_] == $to
        and defined $self->altitudes->[$_]
        and $self->altitudes->[$_] < $max) {
      $max = $self->altitudes->[$_];
    }
  }
  my $delta = 0;
  if    ($roll ==  2) { $delta = -2 }
  elsif ($roll ==  3) { $delta = -1 }
  elsif ($roll ==  4) { $delta = -1 }
  elsif ($roll == 10) { $delta = +1 }
  elsif ($roll == 11) { $delta = +1 }
  elsif ($roll == 12) { $delta = +2 }
  $altitude += $delta;
  $altitude = $max if $altitude > $max;
  $altitude = 0 if $altitude < 0;
  $altitude = 1 if $altitude == 0 and any { defined $self->altitudes->[$_] and $self->altitudes->[$_] > 1  } $self->neighbours($to);
  $self->altitudes->[$to] = $altitude;
}

sub add_flow {
  my ($self, $to) = @_;
  my @neighbours = $self->all_neighbours($to);
  # don't do anything if there's already water flow
  return if defined $self->flows->[$to];
  # don't do anything if this is coastal or ocean
  return if defined $self->altitudes->[$to] and $self->altitudes->[$to] <= 1;
  # if this hex can be a source or water from a neighbour flows into it
  if (not $self->tiles->[$to] and $self->altitudes->[$to] > 1 and $self->altitudes->[$to] < 9
      or any { $self->flows->[$_] and $self->flows->[$_] == $to } @neighbours) {
    # prefer a lower neighbour (or an undefined one), but "lower" works only for
    # known hexes so there must already be water flow, there, and that water
    # flow must not be circular
    my @candidates = grep {
      not defined $self->altitudes->[$_]
          or $self->altitudes->[$_] < $self->altitudes->[$to]
          and $self->flowable($to, $_)
    } shuffle @neighbours;
    if (@candidates) {
      $self->flows->[$to] = $self->pick_with_bias($to, @candidates);
      return;
    }
    # or prefer of equal altitude but again this works only for known hexes so
    # there must already be water flow, there, and that water flow must not be
    # circular
    @candidates = grep {
      $self->altitudes->[$_] == $self->altitudes->[$to]
          and $self->flowable($to, $_)
    } shuffle @neighbours;
    if (@candidates) {
      $self->flows->[$to] = $self->pick_with_bias($to, @candidates);
      return;
    }
    # or dig a canyon? (flow through higher altitudes)
  }
}

# A river can from A to B if B is undefined or if B has flow that doesn't return
# to A.
sub flowable {
  my ($self, $from, $to) = @_;
  while ($self->flows->[$to]) {
    $to = $self->flows->[$to];
    return 0 if $to == $from;
  }
  return 1;
}

# Of all the given neighbours, prefer one with a an existing river; or the one
# in the slope direction; otherwise return the first one. This assumes that they
# are already shuffled.
sub pick_with_bias {
  my ($self, $from, @neighbours) = @_;
  for my $to (@neighbours) {
    my $direction = $self->direction($from, $to);
    if ($direction == $self->slope
        or ($direction + 1) % 6 == $self->slope
        or ($direction - 1) % 6 == $self->slope) {
      return $to;
    }
  }
  return $neighbours[0];
}

sub special {
  return rand() < 1/6;
}

sub roll_2d6 {
  return 2 + int(rand(6)) + int(rand(6));
}

sub neighbour {
  my ($self, $coordinate, $seen) = @_;
  my @neighbours = $self->neighbours($coordinate);
  # If a seen hash reference is provided, prefer new hexes
  if ($seen) {
    my @candidates = grep {!($seen->{$_})} @neighbours;
    return $candidates[0] if @candidates;
  }
  return $neighbours[0];
}

# Returns the coordinates of neighbour regions, in random order, even if off the
# map.
sub all_neighbours {
  my ($self, $coordinate) = @_;
  my @offsets;
  if ($coordinate % 2) {
    @offsets = (-1, +1, $self->cols, -$self->cols, $self->cols -1, $self->cols +1);
  } else {
    @offsets = (-1, +1, $self->cols, -$self->cols, -$self->cols -1, -$self->cols +1);
  }
  return map { $coordinate + $_ } shuffle grep {$_} @offsets;
}

# Returns the coordinates of neighbour regions, in random order, but only if on
# the map.
sub neighbours {
  my ($self, $coordinate) = @_;
  my @offsets;
  if ($coordinate % 2) {
    @offsets = (-1, +1, $self->cols, -$self->cols, $self->cols -1, $self->cols +1);
    $offsets[3] = undef if $coordinate < $self->cols; # top edge
    $offsets[2] = $offsets[4] = $offsets[5] = undef if $coordinate >= ($self->rows - 1) * $self->cols; # bottom edge
    $offsets[0] = $offsets[4] = undef if $coordinate % $self->cols == 0; # left edge
    $offsets[1] = $offsets[5] = undef if $coordinate % $self->cols == $self->cols - 1; # right edge
  } else {
    @offsets = (-1, +1, $self->cols, -$self->cols, -$self->cols -1, -$self->cols +1);
    $offsets[3] = $offsets[4] = $offsets[5] = undef if $coordinate < $self->cols; # top edge
    $offsets[2] = undef if $coordinate >= ($self->rows - 1) * $self->cols; # bottom edge
    $offsets[0] = $offsets[4] = undef if $coordinate % $self->cols == 0; # left edge
    $offsets[1] = $offsets[5] = undef if $coordinate % $self->cols == $self->cols - 1; # right edge
  }
  return map { $coordinate + $_ } shuffle grep {$_} @offsets;
}

# Return the direction of a neighbour given its coordinates. 0 is up (north), 1
# is north-east, 2 is south-east, 3 is south, 4 is south-west, 5 is north-west.
sub direction {
  my ($self, $from, $to) = @_;
  my @offsets;
  if ($from % 2) {
    @offsets = (-$self->cols, +1, $self->cols +1, $self->cols, $self->cols -1, -1);
  } else {
    @offsets = (-$self->cols, -$self->cols +1, +1, $self->cols, -1, -$self->cols -1);
  }
  for (my $i = 0; $i < 6; $i++) {
    return $i if $from + $offsets[$i] == $to;
  }
}

sub to_text {
  my ($self) = @_;
  my $text = "";
  for my $i (0 .. $self->rows * $self->cols - 1) {
    next unless $self->tiles->[$i];
    my @tiles = @{$self->tiles->[$i]};
    push(@tiles, "arrow" . $self->direction($i, $self->flows->[$i])) if defined $self->flows->[$i];
    $text .= $self->xy($i) . " @tiles\n";
  }
  for my $river (@{$self->rivers}) {
    $text .= $self->xy($river) . " river\n" if ref($river) and @$river > 1;
  }
  for my $trail (@{$self->trails}) {
    $text .= $self->xy(@$trail) . " trails\n" if ref($trail) and @$trail > 1;
    # More emphasis
    # $text .= $self->xy(@$trail) . " border\n" if ref($trail) and @$trail > 1;
  }
  # add arrows for the flow
  $text .= join("\n",
                qq{<marker id="arrow" markerWidth="6" markerHeight="6" refX="0" refY="3" orient="auto"><path d="M0,0 V6 L5,3 Z" style="fill: black;" /></marker>},
                map {
                  my $angle = 60 * $_;
                  qq{<path id="arrow$_" transform="rotate($angle)" d="M0,40 V-40" style="stroke: black; stroke-width: 3px; fill: none; marker-end: url(#arrow);"/>};
                } (0 .. 5));
  $text .= "\ninclude bright.txt\n";
  return $text;
}

sub xy {
  my ($self, @coordinates) = @_;
  return join("-", map { sprintf("%02d%02d", $_ % $self->cols + 1, int($_ / $self->cols) + 1) } @coordinates);
}

1;

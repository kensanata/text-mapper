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
use List::Util qw(shuffle sum);
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

has 'rows' => 10;
has 'cols' => 20;
has 'tiles' => sub{[]};
has 'rivers' => sub{[]};
has 'trails' => sub{[]};
has 'altitudes' => sub{[]};
has 'loglevel';

my @tiles = qw(plain rough swamp desert forest hills green-hills forest-hill mountains mountain volcano water coastal ocean);
my @settlements = qw(house ruin ruined-tower ruined-castle tower castle cave);

=head1 METHODS

=head2 generate_map

This method takes no arguments. Set the properties of the map using the
attributes.

=cut

sub generate_map {
  my ($self) = @_;
  $log->level($self->loglevel) if $self->loglevel;
  # random walk
  $self->random_walk();
  return $self->to_text();
}

sub random_walk {
  my ($self) = @_;
  my %seen;
  my $tile_count = 0;
  my $path_length = 1;
  my $max_tiles = $self->rows * $self->cols;
  my $start = $self->rows / 2 * $self->cols + $self->cols / 2;
  # remember those walks for debugging (assign to trails, for example)
  my $walks = [];
  $self->altitudes->[$start] = 5;
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
        push(@{$self->tiles->[$to]}, qq("$tile_count"));
        $tile_count++;
      }
      $from = $to;
      $to = $self->neighbour($from, \%seen);
    }
    $path_length++;
    push(@$walks, $walk);
  }
  return $walks;
}

sub random_tile {
  my ($self, $from, $to) = @_;
  my $roll = roll_2d6();
  my $altitude = $self->adjust_altitude($roll, $from, $to);
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
}

sub adjust_altitude {
  my ($self, $roll, $from, $to) = @_;
  my $altitude = $self->altitudes->[$from];
  if    ($roll ==  2) { $altitude -= 2 if $altitude >= 2 }
  elsif ($roll ==  3) { $altitude -= 1 if $altitude >= 1 }
  elsif ($roll ==  4) { }
  elsif ($roll ==  5) { }
  elsif ($roll ==  6) { }
  elsif ($roll ==  7) { }
  elsif ($roll ==  8) { }
  elsif ($roll ==  9) { }
  elsif ($roll == 10) { }
  elsif ($roll == 11) { $altitude += 1 if $altitude <= 9 }
  elsif ($roll == 12) { $altitude += 2 if $altitude <= 8 }
  else                { die $roll }
  $self->altitudes->[$to] = $altitude;
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

sub to_text {
  my ($self) = @_;
  my $text = "";
  for my $i (0 .. $self->rows * $self->cols - 1) {
    $text .= $self->xy($i) . " @{$self->tiles->[$i]}\n" if $self->tiles->[$i];
  }
  for my $river (@{$self->rivers}) {
    $text .= $self->xy($river) . " river\n" if ref($river) and @$river > 1;
  }
  for my $trail (@{$self->trails}) {
    $text .= $self->xy($trail) . " trail\n" if ref($trail) and @$trail > 1;
  }
  $text .= "\ninclude bright.txt\n";
  return $text;
}

sub xy {
  my ($self, @coordinates) = @_;
  return join("-", map { sprintf("%02d%02d", $_ % $self->cols + 1, int($_ / $self->cols) + 1) } @coordinates);
}

1;

# Copyright (C) 2009-2021  Alex Schroeder <alex@gnu.org>
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

package Game::TextMapper::Mapper::Hex;

use Game::TextMapper::Constants qw($dx $dy);
use Game::TextMapper::Hex;
use Game::TextMapper::Line::Hex;

use Modern::Perl '2018';
use Mojo::Base 'Game::TextMapper::Mapper';

sub make_region {
  my $self = shift;
  return Game::TextMapper::Hex->new(@_);
}

sub make_line {
  my $self = shift;
  return Game::TextMapper::Line::Hex->new(@_);
}

sub shape {
  my $self = shift;
  my $attributes = shift;
  my $points = join(" ", map {
    sprintf("%.1f,%.1f", $_->[0], $_->[1]) } Game::TextMapper::Hex::corners());
  return qq{<polygon $attributes points='$points' />};
}

sub viewbox {
  my $self = shift;
  my ($minx, $miny, $maxx, $maxy) = @_;
  map { int($_) } ($minx * $dx * 3/2 - $dx - 60, ($miny - 1.5) * $dy,
		   $maxx * $dx * 3/2 + $dx + 60, ($maxy + 1) * $dy);
}

1;

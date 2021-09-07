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

package Game::TextMapper::Square;

use Game::TextMapper::Constants qw($dx $dy);

use Game::TextMapper::Point;
use Modern::Perl '2018';
use Mojo::Util qw(url_escape);
use Mojo::Base -base;

has 'x';
has 'y';
has 'z';
has 'type';
has 'label';
has 'size';
has 'map';

sub str {
  my $self = shift;
  return '(' . $self->x . ',' . $self->y . ')';
}

sub svg_region {
  my ($self, $attributes, $offset) = @_;
  my $x = $self->x;
  my $y = $self->y;
  my $z = $self->z;
  my $id = "square$x$y$z";
  $y += $offset->[$z];
  $x = ($x - 0.5) * $dy;
  $y = ($y - 0.5) * $dy; # square!
  return qq{    <rect id="$id" $attributes x="$x" y="$y" width="$dy" height="$dy" />\n}
}

sub svg {
  my ($self, $offset) = @_;
  my $x = $self->x;
  my $y = $self->y;
  my $z = $self->z;
  $y += $offset->[$z];
  my $data = '';
  for my $type (@{$self->type}) {
    $data .= sprintf(qq{    <use x="%d" y="%d" xlink:href="#%s" />\n},
		     $x * $dy,
		     $y * $dy, # square
		     $type);
  }
  return $data;
}

sub svg_coordinates {
  my ($self, $offset) = @_;
  my $x = $self->x;
  my $y = $self->y;
  my $z = $self->z;
  $y += $offset->[$z];
  my $data = '';
  $data .= qq{    <text text-anchor="middle"};
  $data .= sprintf(qq{ x="%d" y="%d"},
		   $x * $dy,
		   ($y - 0.4) * $dy); # square
  $data .= ' ';
  $data .= $self->map->text_attributes || '';
  $data .= '>';
  $data .= Game::TextMapper::Point::coord($self->x, $self->y, "."); # original
  $data .= qq{</text>\n};
  return $data;
}

sub svg_label {
  my ($self, $url, $offset) = @_;
  return '' unless defined $self->label;
  my $attributes = $self->map->label_attributes;
  if ($self->size) {
    if (not $attributes =~ s/\bfont-size="\d+pt"/'font-size="' . $self->size . 'pt"'/e) {
      $attributes .= ' font-size="' . $self->size . '"';
    }
  }
  $url =~ s/\%s/url_escape($self->label)/e or $url .= url_escape($self->label) if $url;
  my $x = $self->x;
  my $y = $self->y;
  my $z = $self->z;
  $y += $offset->[$z];
  my $data = sprintf(qq{    <g><text text-anchor="middle" x="%d" y="%d" %s %s>}
                     . $self->label
                     . qq{</text>},
                     $x  * $dy,
		     ($y + 0.4) * $dy, # square
                     $attributes ||'',
		     $self->map->glow_attributes ||'');
  $data .= qq{<a xlink:href="$url">} if $url;
  $data .= sprintf(qq{<text text-anchor="middle" x="%d" y="%d" %s>}
		   . $self->label
		   . qq{</text>},
		   $x * $dy,
		   ($y + 0.4) * $dy, # square
		   $attributes ||'');
  $data .= qq{</a>} if $url;
  $data .= qq{</g>\n};
  return $data;
}

1;

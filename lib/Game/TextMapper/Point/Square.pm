# Copyright (C) 2009-2022  Alex Schroeder <alex@gnu.org>
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

Game::TextMapper::Point::Square - a square on a map

=head1 SYNOPSIS

    use Modern::Perl;
    use Game::TextMapper::Point::Square;
    my $square = Game::TextMapper::Point::Square->new(x => 1, y => 1, z => 0);
    say $square->svg_region('', [0]);
    # <rect id="square110"  x="86.6" y="86.6" width="173.2" height="173.2" />

=head1 DESCRIPTION

This class holds information about a square region: coordinates, a label, and
types. Types are the kinds of symbols that can be found in the region: a keep, a
tree, a mountain. They correspond to SVG definitions. The class knows how to
draw a SVG rectangle at the correct coordinates using these definitions.

=head1 SEE ALSO

This is a specialisation of L<Game::TextMapper::Point>.

The SVG size is determined by C<$dy> from L<Game::TextMapper::Constants>.

=cut

package Game::TextMapper::Point::Square;

use Game::TextMapper::Constants qw($dy);

use Game::TextMapper::Point;
use Modern::Perl '2018';
use Mojo::Util qw(url_escape);
use Mojo::Base 'Game::TextMapper::Point';
use Encode;

sub pixels {
  my ($self, $offset, $add_x, $add_y) = @_;
  my $x = $self->x;
  my $y = $self->y;
  my $z = $self->z;
  $y += $offset->[$z] if defined $offset->[$z];
  $add_x //= 0;
  $add_y //= 0;
  return $x * $dy + $add_x, $y * $dy + $add_y;
}

sub svg_region {
  my ($self, $attributes, $offset) = @_;
  return sprintf(qq{    <rect id="square%s%s%s" x="%.1f" y="%.1f" width="%.1f" height="%.1f" %s />\n},
		 $self->x, $self->y, $self->z != 0 ? $self->z : '', # z 0 is not printed at all for the $id
		 $self->pixels($offset, -0.5 * $dy, -0.5 * $dy),
		 $dy, $dy, $attributes);
}

sub svg {
  my ($self, $offset) = @_;
  my $data = '';
  for my $type (@{$self->type}) {
    $data .= sprintf(qq{    <use x="%.1f" y="%.1f" xlink:href="#%s" />\n},
		     $self->pixels($offset),
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
  $data .= sprintf(qq{ x="%.1f" y="%.1f"}, $self->pixels($offset, 0, -0.4 * $dy));
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
  $url =~ s/\%s/url_escape(encode_utf8($self->label))/e or $url .= url_escape(encode_utf8($self->label)) if $url;
  my $data = "    <g>";
  sprintf('<text text-anchor="middle" x="%.1f" y="%.1f" %s %s>%s</text>',
          $self->pixels($offset, 0, 0.4 * $dy),
          $attributes ||'',
          $self->map->glow_attributes,
          $self->label)
      if $self->map->glow_attributes;
  $data .= qq{<a xlink:href="$url">} if $url;
  $data .= sprintf(qq{<text text-anchor="middle" x="%.1f" y="%.1f" %s>%s</text>},
		   $self->pixels($offset, 0, 0.4 * $dy),
		   $attributes ||'',
		   $self->label);
  $data .= "</a>" if $url;
  $data .= "</g>\n";
  return $data;
}

1;

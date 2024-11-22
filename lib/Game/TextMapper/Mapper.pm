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

Game::TextMapper::Mapper - a text map parser and builder

=head1 SYNOPSIS

    use Modern::Perl;
    use Game::TextMapper::Mapper::Hex;
    my $map = <<EOT;
    0101 forest
    include default.txt
    EOT
    my $svg = Game::TextMapper::Mapper::Hex->new(dist_dir => 'share')
      ->initialize($map)
      ->svg();
    print $svg;

=head1 DESCRIPTION

This class knows how to parse a text containing a map description into SVG
definitions, and regions. Once the map is built, this class knows how to
generate the SVG for the entire map.

The details depend on whether the map is a hex map or a square map. You should
use the appropriate class instead of this one: L<Game::TextMapper::Mapper::Hex>
or L<Game::TextMapper::Mapper::Square>.

=cut

package Game::TextMapper::Mapper;
use Game::TextMapper::Log;
use Modern::Perl '2018';
use Mojo::UserAgent;
use Mojo::Base -base;
use File::Slurper qw(read_text);
use Encode qw(encode_utf8 decode_utf8);
use Mojo::Util qw(url_escape);
use File::ShareDir 'dist_dir';
use Scalar::Util 'weaken';

=head1 ATTRIBUTES

=head2 dist_dir

You need to pass this during instantiation so that the mapper knows where to
find files it needs to include.

=cut

has 'local_files';
has 'dist_dir';
has 'map';
has 'regions' => sub { [] };
has 'attributes' => sub { {} };
has 'defs' => sub { [] };
has 'path' => sub { {} };
has 'lines' => sub { [] };
has 'things' => sub { [] };
has 'path_attributes' => sub { {} };
has 'text_attributes' => '';
has 'glow_attributes' => '';
has 'label_attributes' => '';
has 'messages' => sub { [] };
has 'seen' => sub { {} };
has 'license' => '';
has 'other' => sub { [] };
has 'url' => '';
has 'offset' => sub { [] };

my $log = Game::TextMapper::Log->get;

sub example {
  return <<"EOT";
0101 mountain "mountain"
0102 swamp "swamp"
0103 hill "hill"
0104 forest "forest"
0201 empty pyramid "pyramid"
0202 tundra "tundra"
0203 coast "coast"
0204 empty house "house"
0301 woodland "woodland"
0302 wetland "wetland"
0303 plain "plain"
0304 sea "sea"
0401 hill tower "tower"
0402 sand house "house"
0403 jungle "jungle"
0501 mountain cave "cave"
0502 sand "sand"
0503 hill castle "castle"
0205-0103-0202-0303-0402 road
0101-0203 river
0401-0303-0403 border
include default.txt
license <text>Public Domain</text>
EOT
}

=head1 METHODS

=head2 initialize($map)

Call this to load a map into the mapper.

=cut

sub initialize {
  my ($self, $map) = @_;
  $map =~ s/&#45;/-/g; # -- are invalid in source comments...
  $self->map($map);
  $self->process(split(/\r?\n/, $map));
}

sub process {
  my $self = shift;
  my $line_id = 0;
  foreach (@_) {
    if (/^(-?\d\d)(-?\d\d)(\d\d)?\s+(.*)/ or /^(-?\d\d+)\.(-?\d\d+)(?:\.(\d\d+))?\s+(.*)/) {
      my $region = $self->make_region(x => $1, y => $2, z => $3||'00', map => $self);
      weaken($region->{map});
      my $rest = $4;
      while (my ($tag, $label, $size) = $rest =~ /\b([a-z]+)=["“]([^"”]+)["”]\s*(\d+)?/) {
	if ($tag eq 'name') {
	  $region->label($label);
          $region->size($size) if $size;
	} else {
	  # delay the calling of $self->other_info because the URL or the $self->glow_attributes might not be set
	  push(@{$self->other()}, sub () { $self->other_info($region, $label, $size, "translate(0,45)", 'opacity="0.2"') });
        }
	$rest =~ s/\b([a-z]+)=["“]([^"”]+)["”]\s*(\d+)?//;
      }
      while (my ($label, $size, $transform) = $rest =~ /["“]([^"”]+)["”]\s*(\d+)?((?:\s*[a-z]+\([^\)]+\))*)/) {
	if ($transform or $region->label) {
	  # delay the calling of $self->other_text because the URL or the $self->glow_attributes might not be set
	  push(@{$self->other()}, sub () { $self->other_text($region, $label, $size, $transform) });
	} else {
	  $region->label($label);
	  $region->size($size);
	}
	$rest =~ s/["“]([^"”]+)["”]\s*(\d+)?((?:\s*[a-z]+\([^\)]+\))*)//;
      }
      my @types = split(/\s+/, $rest);
      $region->type(\@types);
      push(@{$self->regions}, $region);
      push(@{$self->things}, $region);
    } elsif (/^(-?\d\d-?\d\d(?:\d\d)?(?:--?\d\d-?\d\d(?:\d\d)?)+)\s+(\S+)\s*(?:["“](.+)["”])?\s*(left|right)?\s*(\d+%)?/
             or /^(-?\d\d+\.-?\d\d+(?:\.\d\d+)?(?:--?\d\d+\.-?\d\d+(?:\.\d\d+)?)+)\s+(\S+)\s*(?:["“](.+)["”])?\s*(left|right)?\s*(\d+%)?/) {
      my $line = $self->make_line(map => $self);
      weaken($line->{map});
      my $str = $1;
      $line->type($2);
      $line->label($3);
      $line->side($4);
      $line->start($5);
      $line->id('line' . $line_id++);
      my @points;
      while ($str =~ /\G(?:(-?\d\d)(-?\d\d)(\d\d)?|(-?\d\d+)\.(-?\d\d+)\.(\d\d+)?)-?/cg) {
	push(@points, Game::TextMapper::Point->new(x => $1||$4, y => $2||$5, z => $3||$6||'00'));
      }
      $line->points(\@points);
      push(@{$self->lines}, $line);
    } elsif (my ($name, $x, $y, $starport, $size, $atmosphere, $hydrographic, $population, $government, $law, $tech, $bases, $rest) =
        /(?:([^>\r\n\t]*?)\s+)?(\d\d)(\d\d)\s+([A-EX])([\dA])([\dA-F])([\dA])([\dA-C])([\dA-F])([\dA-L])-(\d{1,2}|[\dA-HJ-NP-Z])(?:\s+([PCTRNSG ]+)\b)?(.*)/) {
      my $region = $self->make_region(x => $x, y => $y, z => '00', map => $self);
      weaken($region->{map});
      my @types;
      push(@types, "starport-$starport") if $starport;
      push(@types, "consulate") if $bases =~ /C/;
      push(@types, "tas") if $bases =~ /T/;
      push(@types, "pirate") if $bases =~ /P/;
      push(@types, "research") if $bases =~ /R/;
      push(@types, "naval") if $bases =~ /N/;
      push(@types, "gas") if $bases =~ /G/;
      push(@types, "scout") if $bases =~ /S/;
      push(@types, "size-$size");
      push(@types, "atmosphere-$atmosphere");
      push(@types, "hydrosphere-$hydrographic");
      push(@types, "population-$population");
      push(@types, "government-$government");
      push(@types, "law-$law");
      push(@types, "tech-$tech");
      my @tokens = split(' ', $rest);
      my %map = (A => "amber", R => "red");
      my ($travelzone) = grep /^([AR])$/, @tokens; # amber or red travel zone
      push(@types, $map{$travelzone}) if $travelzone;
      push(@types, grep(/^[A-Z][A-Za-z]$/, @tokens));
      $region->type(\@types);
      $region->label($name);
      $region->size($size);
      push(@{$self->regions}, $region);
      push(@{$self->things}, $region);
    } elsif (/^(\S+)\s+attributes\s+(.*)/) {
      $self->attributes->{$1} = $2;
    } elsif (/^(\S+)\s+lib\s+(.*)/) {
      $self->def(qq{<g id="$1">$2</g>});
    } elsif (/^(\S+)\s+xml\s+(.*)/) {
      $self->def(qq{<g id="$1">$2</g>});
    } elsif (/^(<.*>)/) {
      $self->def($1);
    } elsif (/^(\S+)\s+path\s+attributes\s+(.*)/) {
      $self->path_attributes->{$1} = $2;
    } elsif (/^(\S+)\s+path\s+(.*)/) {
      $self->path->{$1} = $2;
    } elsif (/^text\s+(.*)/) {
      $self->text_attributes($1);
    } elsif (/^glow\s+(.*)/) {
      $self->glow_attributes($1);
    } elsif (/^label\s+(.*)/) {
      $self->label_attributes($1);
    } elsif (/^license\s+(.*)/) {
      $self->license($1);
    } elsif (/^other\s+(.*)/) {
      push(@{$self->other()}, $1);
    } elsif (/^url\s+(\S+)/) {
      $self->url($1);
    } elsif (/^include\s+(\S*)/) {
      if (scalar keys %{$self->seen} > 5) {
	push(@{$self->messages},
	     "Includes are limited to five to prevent loops");
      } elsif (not $self->seen->{$1}) {
	my $location = $1;
	$self->seen->{$location} = 1;
	my $path;
	if (index($location, '/') == -1 and -f ($path = Mojo::File->new($self->dist_dir, $location))) {
	  # without a slash, it could be a file from dist_dir
	  $log->debug("Reading $location");
	  $self->process(split(/\n/, decode_utf8($path->slurp())));
	} elsif ($self->local_files and -f ($path = Mojo::File->new($location))) {
	  # it could also be a local file in the same directory, but only if
	  # called from the render command (which sets local_files)
	  $log->debug("Reading $location");
	  $self->process(split(/\n/, decode_utf8($path->slurp())));
	} elsif ($location =~ /^https?:/) {
	  $log->debug("Getting $location");
	  my $ua = Mojo::UserAgent->new;
	  my $response = $ua->get($location)->result;
	  if ($response->is_success) {
	    $self->process(split(/\n/, $response->text));
	  } else {
	    push(@{$self->messages}, "Getting $location: " . $response->status_line);
	  }
	} elsif ($self->dist_dir =~ /^https?:/) {
	  my $url = $self->dist_dir;
	  $url .= '/' unless $url =~ /\/$/;
	  $url .= $location;
	  $log->debug("Getting $url");
	  my $ua = Mojo::UserAgent->new;
	  my $response = $ua->get($url)->result;
	  if ($response->is_success) {
	    $self->process(split(/\n/, $response->text));
	  } else {
	    push(@{$self->messages}, "Getting $url: " . $response->status_line);
	  }
	} else {
	  $log->warn("No library '$location' in " . $self->dist_dir);
	  push(@{$self->messages}, "Library '$location' is must be an existing file on the server or a HTTP/HTTPS URL");
	}
      }
    } else {
      $log->debug("Did not parse $_") if $_ and not /^\s*#/;
    }
  }
  return $self;
}

sub svg_other {
  my ($self) = @_;
  my $data = "\n";
  for my $other (@{$self->other()}) {
    if (ref $other eq 'CODE') {
      $data .= $other->();
    } else {
      $data .= $other;
    }
    $data .= "\n";
  }
  $self->other(undef);
  return $data;
}

# Very similar to svg_label, but given that we have a transformation, we
# translate the object to it's final position.
sub other_text {
  my ($self, $region, $label, $size, $transform) = @_;
  $transform = sprintf("translate(%.1f,%.1f)", $region->pixels($self->offset)) . $transform;
  my $attributes = "transform=\"$transform\" " . $self->label_attributes;
  if ($size and not $attributes =~ s/\bfont-size="\d+pt"/font-size="$size"/) {
    $attributes .= " font-size=\"$size\"";
  }
  my $data = sprintf(qq{    <g><text text-anchor="middle" %s %s>%s</text>},
                     $attributes, $self->glow_attributes||'', $label);
  my $url = $self->url;
  $url =~ s/\%s/url_escape(encode_utf8($label))/e or $url .= url_escape(encode_utf8($label)) if $url;
  $data .= sprintf(qq{<a xlink:href="%s"><text text-anchor="middle" %s>%s</text></a>},
		   $url, $attributes, $label);
  $data .= qq{</g>\n};
  return $data;
}

# Very similar to other_text, but without a link and we have extra attributes
sub other_info {
  my ($self, $region, $label, $size, $transform, $attributes) = @_;
  $transform = sprintf("translate(%.1f,%.1f)", $region->pixels($self->offset)) . $transform;
  $attributes .= " transform=\"$transform\"";
  $attributes .= " " . $self->label_attributes if $self->label_attributes;
  if ($size and not $attributes =~ s/\bfont-size="\d+pt"/font-size="$size"/) {
    $attributes .= " font-size=\"$size\"";
  }
  my $data = sprintf(qq{    <g><text text-anchor="middle" %s %s>%s</text>}, $attributes, $self->glow_attributes||'', $label);
  $data .= sprintf(qq{<text text-anchor="middle" %s>%s</text></g>\n}, $attributes, $label);
  return $data;
}

sub def {
  my ($self, $svg) = @_;
  $svg =~ s/>\s+</></g;
  push(@{$self->defs}, $svg);
}

sub merge_attributes {
  my %attr = ();
  for my $attr (@_) {
    if ($attr) {
      while ($attr =~ /(\S+)=((["']).*?\3)/g) {
        $attr{$1} = $2;
      }
    }
  }
  return join(' ', map { $_ . '=' . $attr{$_} } sort keys %attr);
}

sub svg_header {
  my ($self) = @_;

  my $header = qq{<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<svg xmlns="http://www.w3.org/2000/svg" version="1.1"
     xmlns:xlink="http://www.w3.org/1999/xlink"
};
  return $header . "\n" unless @{$self->regions};
  my $maxz = 0;
  foreach my $region (@{$self->regions}) {
    $maxz = $region->z if $region->z > $maxz;
  }
  # These are required to calculate the viewBox for the SVG. Min and max X are
  # what you would expect. Min and max Y are different, however, since we want
  # to count all the rows on all the levels, plus an extra separator between
  # them. Thus, min y is the min y of the first level, and max y is the min y of
  # the first level + 1 for every level beyond the first, + all the rows for
  # each level.
  my $min_x_overall;
  my $max_x_overall;
  my $min_y_overall;
  my $max_y_overall;
  for my $z (0 .. $maxz) {
    my ($minx, $miny, $maxx, $maxy);
    $self->offset->[$z] = $max_y_overall // 0;
    foreach my $region (@{$self->regions}) {
      next unless $region->z == $z;
      $minx = $region->x unless defined $minx and $minx <= $region->x;
      $maxx = $region->x unless defined $maxx and $maxx >= $region->x;
      $miny = $region->y unless defined $miny and $miny <= $region->y;
      $maxy = $region->y unless defined $maxy and $maxy >= $region->y;
    }
    $min_x_overall = $minx unless defined $min_x_overall and $minx >= $min_x_overall;
    $max_x_overall = $maxx unless defined $min_y_overall and $maxx <= $max_x_overall;;
    $min_y_overall = $miny unless defined $min_y_overall; # first row of the first level
    $max_y_overall = $miny unless defined $max_y_overall; # also (!) first row of the first level
    $max_y_overall += 1 if $z > 0; # plus a separator row for every extra level
    $max_y_overall += 1 + $maxy - $miny; # plus the number of rows for every level
  }
  my ($vx1, $vy1, $vx2, $vy2) = $self->viewbox($min_x_overall, $min_y_overall, $max_x_overall, $max_y_overall);
  my ($width, $height) = ($vx2 - $vx1, $vy2 - $vy1);
  $header .= qq{     viewBox="$vx1 $vy1 $width $height">\n};
  $header .= qq{     <!-- min ($min_x_overall, $min_y_overall), max ($max_x_overall, $max_y_overall) -->\n};
  return $header;
}

sub svg_defs {
  my ($self) = @_;
  # All the definitions are included by default.
  my $doc = "  <defs>\n";
  $doc .= "    " . join("\n    ", @{$self->defs}, "") if @{$self->defs};
  # collect region types from attributess and paths in case the sets don't overlap
  my %types = ();
  foreach my $region (@{$self->regions}) {
    foreach my $type (@{$region->type}) {
      $types{$type} = 1;
    }
  }
  foreach my $line (@{$self->lines}) {
    $types{$line->type} = 1;
  }
  # now go through them all
  foreach my $type (sort keys %types) {
    my $path = $self->path->{$type};
    my $attributes = merge_attributes($self->attributes->{$type});
    my $path_attributes = merge_attributes($self->path_attributes->{'default'},
					   $self->path_attributes->{$type});
    my $glow_attributes = $self->glow_attributes;
    if ($path || $attributes) {
      $doc .= qq{    <g id="$type">\n};
      # just shapes get a glow such, eg. a house (must come first)
      if ($path && !$attributes) {
	$doc .= qq{      <path $glow_attributes d='$path' />\n}
      }
      # region with attributes get a shape (square or hex), eg. plains and grass
      if ($attributes) {
	$doc .= "      " . $self->shape($attributes) . "\n";
      }
      # and now the attributes themselves the shape itself
      if ($path) {
      $doc .= qq{      <path $path_attributes d='$path' />\n}
      }
      # close
      $doc .= qq{    </g>\n};
    } else {
      # nothing
    }
  }
  $doc .= qq{  </defs>\n};
}

sub svg_backgrounds {
  my $self = shift;
  my $doc = qq{  <g id="backgrounds">\n};
  foreach my $thing (@{$self->things}) {
    # make a copy
    my @types = @{$thing->type};
    # keep attributes
    $thing->type([grep { $self->attributes->{$_} } @{$thing->type}]);
    $doc .= $thing->svg($self->offset);
    # reset copy
    $thing->type(\@types);
  }
  $doc .= qq{  </g>\n};
  return $doc;
}

sub svg_things {
  my $self = shift;
  my $doc = qq{  <g id="things">\n};
  foreach my $thing (@{$self->things}) {
    # drop attributes
    $thing->type([grep { not $self->attributes->{$_} } @{$thing->type}]);
    $doc .= $thing->svg($self->offset);
  }
  $doc .= qq{  </g>\n};
  return $doc;
}

sub svg_coordinates {
  my $self = shift;
  my $doc = qq{  <g id="coordinates">\n};
  foreach my $region (@{$self->regions}) {
    $doc .= $region->svg_coordinates($self->offset);
  }
  $doc .= qq{  </g>\n};
  return $doc;
}

sub svg_lines {
  my $self = shift;
  my $doc = qq{  <g id="lines">\n};
  foreach my $line (@{$self->lines}) {
    $doc .= $line->svg($self->offset);
  }
  $doc .= qq{  </g>\n};
  return $doc;
}

sub svg_regions {
  my $self = shift;
  my $doc = qq{  <g id="regions">\n};
  my $attributes = $self->attributes->{default} || qq{fill="none"};
  foreach my $region (@{$self->regions}) {
    $doc .= $region->svg_region($attributes, $self->offset);
  }
  $doc .= qq{  </g>\n};
}

sub svg_line_labels {
  my $self = shift;
  my $doc = qq{  <g id="line_labels">\n};
  foreach my $line (@{$self->lines}) {
    $doc .= $line->svg_label($self->offset);
  }
  $doc .= qq{  </g>\n};
  return $doc;
}

sub svg_labels {
  my $self = shift;
  my $doc = qq{  <g id="labels">\n};
  foreach my $region (@{$self->regions}) {
    $doc .= $region->svg_label($self->url, $self->offset);
  }
  $doc .= qq{  </g>\n};
  return $doc;
}

=head2 svg()

This method generates the SVG once the map is initialized.

=cut

sub svg {
  my ($self) = @_;

  my $doc = $self->svg_header();
  $doc .= $self->svg_defs();
  $doc .= $self->svg_backgrounds(); # opaque backgrounds
  $doc .= $self->svg_lines();
  $doc .= $self->svg_things(); # icons, lines
  $doc .= $self->svg_coordinates();
  $doc .= $self->svg_regions();
  $doc .= $self->svg_line_labels();
  $doc .= $self->svg_labels();
  $doc .= $self->license() ||'';
  $doc .= $self->svg_other();

  # error messages
  my $y = 10;
  foreach my $msg (@{$self->messages}) {
    $doc .= "  <text x='0' y='$y'>$msg</text>\n";
    $y += 10;
  }

  # source code (comments may not include -- for SGML compatibility!)
  # https://stackoverflow.com/questions/10842131/xml-comments-and
  my $source = $self->map();
  $source =~ s/--/&#45;&#45;/g;
  $doc .= "<!-- Source\n$source\n-->\n";
  $doc .= qq{</svg>\n};

  return $doc;
}

=head1 SEE ALSO

L<Game::TextMapper::Mapper::Hex> is for hex maps.

L<Game::TextMapper::Mapper::Square> is for square maps.

=cut

1;

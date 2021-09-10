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

package Mojolicious::Command::render;
use Modern::Perl '2018';
use Mojo::Base 'Mojolicious::Command';
use File::ShareDir 'dist_dir';

has description => 'Render map from STDIN';

has usage => <<EOF;
Usage example:

    text-mapper render < share/forgotten-depths.txt > forgotten-depths.svg

This reads a map description from STDIN and prints the resulting SVG map to
STDOUT.
EOF

sub run {
  my ($self, @args) = @_;
  local $/ = undef;
  my $dist_dir = $self->app->config('contrib') // dist_dir('Game-TextMapper');
  my $mapper = Game::TextMapper::Mapper::Hex->new(dist_dir => $dist_dir);
  $mapper->initialize(<STDIN>);
  print $mapper->svg;
}

1;

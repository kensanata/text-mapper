# Copyright (C) 2021  Alex Schroeder <alex@gnu.org>

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
# with this program. If not, see <https://www.gnu.org/licenses/>.

use Modern::Perl;
use Test::More;
use Test::Mojo;
use utf8;

my $t = Test::Mojo->new('Game::TextMapper');

my $stash;
$t->app->hook(after_dispatch => sub { my $c = shift; $stash = $c->stash });

$t->get_ok('/')
    ->status_is(200)
    ->text_is('h1' => 'Text Mapper')
    ->text_like('textarea[name=map]' => qr/^0101 mountain "mountain"$/m);

my $map = <<EOT;
grass attributes fill="green"
0101 grass
EOT

$t->post_ok('/render' => form => {map => $map})
    ->status_is(200)
    ->element_exists('defs g#grass polygon[fill=green]')
    # I don't know how to use a namespace for attributes
    ->element_exists('g#backgrounds use[x=150.0][y=86.6]')
    ->text_is('g#coordinates text[x=150.0][y=17.3]', "01.01")
    ->element_exists('g#regions polygon#hex010100');

$t->post_ok('/render' => form => {map => $map, type => 'square'})
    ->status_is(200)
    ->element_exists('defs g#grass rect[fill=green]')
    # I don't know how to use a namespace for attributes
    ->element_exists('g#backgrounds use[x=173][y=173]')
    ->text_is('g#coordinates text[x=173][y=103]', "01.01")
    ->element_exists('g#regions rect#square010100');

# warn $t->tx->res->body;

done_testing;

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
use IPC::Open2;
use Mojo::DOM;
use Test::Mojo;

# random

like(qx(script/text-mapper random), qr/^0101/, 'random');

# render

# setup
my $pid = open2(my $out, my $in, 'script/text-mapper', 'render');
print $in "0101 forest\n";
close($in);
# read and parse output
undef $/;
my $data = <$out>;
my $dom = Mojo::DOM->new($data);
# testing
ok($dom->at("g#things use"), "things");
is($dom->at("g#coordinates text")->text, "01.01", "text");
ok($dom->at("g#regions polygon#hex010100"), "text");
# reap zombie and retrieve exit status
waitpid($pid, 0);
my $child_exit_status = $? >> 8;
is($child_exit_status, 0, "Exit status OK");

done_testing;

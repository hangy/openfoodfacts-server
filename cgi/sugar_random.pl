#!/usr/bin/perl -w

# This file is part of Product Opener.
#
# Product Opener
# Copyright (C) 2011-2023 Association Open Food Facts
# Contact: contact@openfoodfacts.org
# Address: 21 rue des Iles, 94100 Saint-Maur des Fossés, France
#
# Product Opener is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

use ProductOpener::PerlStandards;

use CGI::Carp qw(fatalsToBrowser);
use CGI qw/:cgi :form escapeHTML/;
use Encode;
use JSON::MaybeXS;
#11872 Need to use PO Storable
use Storable qw(lock_store lock_nstore lock_retrieve);
use Apache2::RequestRec ();
use Apache2::Const ();

use List::Util qw(shuffle);
use Log::Any qw($log);

use ProductOpener::Paths qw/%BASE_DIRS/;

# this script is used by howmuchsugar to redirect to a new product randomly

my $r = Apache2::RequestUtil->request();

# read site name in apache provided header
my $lang = $r->headers_in->{"X-Site-Lang"} // 'en';

my $ids_ref = lock_retrieve($BASE_DIRS{PRIVATE_DATA} . "/sugar/$lang/products_ids.sto")
	or die("Cannot open sugar/products_ids.sto");
my @ids = @$ids_ref;

srand();

my @shuffle = shuffle(@ids);

my $id = pop(@shuffle);

$log->info("random ids sampled", {ids => scalar(@ids), id => $id}) if $log->is_info();

$r->headers_out->set(Location => "/$id");
$r->headers_out->set(Pragma => "no-cache");
$r->headers_out->set("Cache-control" => "no-cache");
$r->status(302);
return 302;


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

use ProductOpener::Config qw/:all/;
use ProductOpener::Store qw/:all/;
use ProductOpener::Display qw/init_request/;
use ProductOpener::HTTP qw/write_cors_headers single_param/;
use ProductOpener::Users qw/$User_id %User is_admin_user/;
use ProductOpener::Lang qw/:all/;
use ProductOpener::Tags qw/country_to_cc/;

use Apache2::Const -compile => qw(OK);
use CGI qw/:cgi :form escapeHTML/;
use URI::Escape::XS;
use Encode;
use Log::Any qw($log);
use JSON::MaybeXS;

$log->info('start') if $log->is_info();

my $request_ref = ProductOpener::Display::init_request();

my $status;
my $response_ref;

if (defined $User_id) {
	$status = 200;

	# Return basic data about the user

	my $user_ref = {
		name => $User{name},
		moderator => $User{moderator} ? 1 : 0,
		admin => is_admin_user($User_id) ? 1 : 0,
	};

	# Add some fields if we have defined and non empty values for them
	if ($User{preferred_language}) {
		$user_ref->{preferred_language} = $User{preferred_language};
	}
	if ($User{country}) {
		$user_ref->{country} = $User{country};
		my $cc = country_to_cc($User{country});
		if ($cc) {
			$user_ref->{cc} = $cc;
		}
	}

	$response_ref = {
		status => 1,
		status_verbose => 'user signed-in',
		user_id => $User_id,
		user => $user_ref,
	};
}
else {
	$status = 403;
	$response_ref = {
		status => 0,
		status_verbose => 'user not signed-in',
	};
}

my $json = JSON::MaybeXS->new->allow_nonref->canonical->utf8->encode($response_ref);

# We need to send the header Access-Control-Allow-Credentials=true so that websites
# such has hunger.openfoodfacts.org that send a query to world.openfoodfacts.org/cgi/auth.pl
# can read the resulting response.

# The Access-Control-Allow-Origin header must be set to the value of the Origin header
my $r = Apache2::RequestUtil->request();
my $allow_credentials = 1;
write_cors_headers($allow_credentials);
# Write a session cookie if we were passed a user id and password
if ($request_ref->{cookie}) {
	$r->err_headers_out->add('Set-Cookie' => $request_ref->{cookie});
}
print header(-status => $status, -type => 'application/json', -charset => 'utf-8');

# 2022-10-11 - The Open Food Facts Flutter app is expecting an empty body
# see https://github.com/openfoodfacts/smooth-app/issues/3118
# only send a body if we have the body=1 parameter
# TODO: remove this condition when new versions of the app are deployed
if (single_param("body")) {
	print $json;
}

$r->rflush;

# Setting the status makes mod_perl append a default error to the body
# $r->status($status);
# Send 200 instead.
$r->status(200);

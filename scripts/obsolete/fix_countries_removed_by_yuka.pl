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

use Modern::Perl '2017';
use utf8;

my $usage = <<TXT
update_all_products.pl is a script that updates the latest version of products in the file system and on MongoDB.
It is used in particular to re-run tags generation when taxonomies have been updated.

Usage:

update_all_products.pl --key some_string_value --fields categories,labels --index

The key is used to keep track of which products have been updated. If there are many products and field to updates,
it is likely that the MongoDB cursor of products to be updated will expire, and the script will have to be re-run.

--process-ingredients	compute allergens, additives detection

--compute-nutrition-score	nutriscore

--check-quality	run quality checks

--index		specifies that the keywords used by the free text search function (name, brand etc.) need to be reindexed. -- TBD

--pretend	do not actually update products
TXT
;

use CGI::Carp qw(fatalsToBrowser);

use ProductOpener::Config qw/:all/;
use ProductOpener::Paths qw/:all/;
use ProductOpener::Store qw/:all/;
use ProductOpener::Index qw/:all/;
use ProductOpener::Display qw/:all/;
use ProductOpener::Tags qw/:all/;
use ProductOpener::Users qw/:all/;
use ProductOpener::Images qw/:all/;
use ProductOpener::Lang qw/:all/;
use ProductOpener::Mail qw/:all/;
use ProductOpener::Products qw/:all/;
use ProductOpener::Food qw/:all/;
use ProductOpener::Ingredients qw/:all/;
use ProductOpener::Images qw/:all/;

use CGI qw/:cgi :form escapeHTML/;
use URI::Escape::XS;
use Storable qw/dclone/;
use Encode;
use JSON::MaybeXS;

use Getopt::Long;



# traverse the history to see if a particular user has removed values for tag fields
# add back the removed values

# NOT sure if this is useful, it's being used in one of the "obsolete" scripts
sub add_back_field_values_removed_by_user ($current_product_ref, $changes_ref, $field, $userid) {

	my $code = $current_product_ref->{code};
	my $path = product_path($current_product_ref);

	return if not defined $changes_ref;

	# Read all previous versions to see which fields have been added or edited

	my @fields
		= qw(lang product_name generic_name quantity packaging brands categories origins manufacturing_places labels emb_codes expiration_date purchase_places stores countries ingredients_text traces no_nutrition_data serving_size nutrition_data_per );

	my %previous = ();
	my %last = %previous;
	my %current;

	my $previous_tags_ref = {};
	my $current_tags_ref;

	my %removed_tags = ();

	my $revs = 0;

	foreach my $change_ref (@{$changes_ref}) {
		$revs++;
		my $rev = $change_ref->{rev};
		if (not defined $rev) {
			$rev = $revs;    # was not set before June 2012
		}
		my $product_ref = retrieve_object("$BASE_DIRS{PRODUCTS}/$path/$rev");

		# if not found, we may be be updating the product, with the latest rev not set yet
		if ((not defined $product_ref) or ($rev == $current_product_ref->{rev})) {
			$product_ref = $current_product_ref;
			if (not defined $product_ref) {
				$log->warn("specified product revision was not found, using current product ref",
					{code => $code, revision => $rev})
					if $log->is_warn();
			}
		}

		if (defined $product_ref->{$field . "_tags"}) {

			$current_tags_ref = {map {$_ => 1} @{$product_ref->{$field . "_tags"}}};
		}
		else {
			$current_tags_ref = {};
		}

		if ((defined $change_ref->{userid}) and ($change_ref->{userid} eq $userid)) {

			foreach my $tagid (keys %{$previous_tags_ref}) {
				if (not exists $current_tags_ref->{$tagid}) {
					$log->info("user removed value for a field",
						{user_id => $userid, tagid => $tagid, field => $field, code => $code})
						if $log->is_info();
					$removed_tags{$tagid} = 1;
				}
			}
		}

		$previous_tags_ref = $current_tags_ref;

	}

	my $added = 0;
	my $added_countries = "";

	foreach my $tagid (sort keys %removed_tags) {
		if (not exists $current_tags_ref->{$tagid}) {
			$log->info("adding back removed tag", {tagid => $tagid, field => $field, code => $code}) if $log->is_info();

			# we do not know the language of the current value of $product_ref->{$field}
			# so regenerate it in the main language of the product
			my $value = display_tags_hierarchy_taxonomy($lc, $field, $current_product_ref->{$field . "_hierarchy"});
			# Remove tags
			$value =~ s/<(([^>]|\n)*)>//g;

			$current_product_ref->{$field} .= $value . ", $tagid";

			if ($current_product_ref->{$field} =~ /^, /) {
				$current_product_ref->{$field} = $';
			}

			compute_field_tags($current_product_ref, $current_product_ref->{lc}, $field);

			$added++;
			$added_countries .= " $tagid";
		}
	}

	if ($added > 0) {

		return $added . $added_countries;
	}
	else {
		return 0;
	}
}


my @fields_to_update = ();
my $key;


GetOptions ("key=s"   => \$key,      # string

			)
  or die("Error in command line arguments:\n$\nusage");

# Get a list of all products not yet updated

my $query_ref = {};
if (defined $key) {
	
}
else {
	$key = "key_" . time();
}

$query_ref = { editors_tags => "kiliweb", update_key => { '$ne' => "$key" } };

print "Update key: $key\n\n";

my $cursor = $products_collection->query($query_ref)->fields({ code => 1 });
$cursor->immortal(1);

my $n = 1;
my $changed_products = 0;
my $added_fields = 0;
	
while (my $product_ref = $cursor->next) {
	
	my $code = $product_ref->{code};
	my $path = product_path($code);
	
	#next if $code ne "9555118659523";
	
	(($n % 100) == 0) and print STDERR $n . " products checked\n";
	
	$n++;

	my $changes_ref = retrieve_object("$BASE_DIRS{PRODUCTS}/$path/changes.sto");
	if ( not defined $changes_ref ) {
		next;
	}

	$product_ref = retrieve_product($code);
	
	if ((defined $product_ref) and ($code ne '')) {
	
		my $added = add_back_field_values_removed_by_user($product_ref, $changes_ref, "countries", "kiliweb");
	
		
		if ($added ne "0") {
			
			my $added_n = 0;
			if ($added =~ /^(\d+) /) {
				$added_n = $1;
				$added = $';
			}
				
			$added_fields += $added_n;
			$changed_products ++;
			
			#next;
			
			$User_id = 'yukafix';
			store_product($product_ref, "fix_countries_removed_by_yuka.pl - add back countries removed by yuka: $added");
			
			exit;
		}
		
		
	}

}
			
print "$changed_products products updated - $added_fields fields added\n";
			
exit(0);


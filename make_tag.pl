#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;


my $tagName = '';
my $tagPath = '';	
my $source = '';

my $cmd;


GetOptions ('tag=s' => \$tagPath, 'source=s' => \$source);
    
if ( ( $tagPath eq '' ) || ($source eq '' ) )
{
	printHelp();
	exit;
}

sub runningLatestVersion
{
	my $script = $0;

	my $cmd = "svn status --show-updates $script";

	my $scriptInfo = `$cmd`;


	if (index($scriptInfo,'*') ne -1)
	{
		#It looks like the script is out of date.......
#		print "\t(INFO-$scriptInfo)\n";
		return 0;
	}

	return 1;
}

#if ( !runningLatestVersion() ) 
#{
#	print "Your script is out of date, please update it first\n";
#	exit;
#}

print "\nMake Tag Script\n\n";

#Get the URL for the code path specified on the command line
my $sourceUrl = getSvnInfo('URL', $source);


if (index($sourceUrl, '@') ne -1 )
{
	print "Found username in the URL: $sourceUrl\n";

	my $repositoryRoot = getSvnInfo('Repository Root', $source);

	my $start = index($repositoryRoot,"//");
	my $end   = index($repositoryRoot, '@');
	
	my $newUrl = substr($repositoryRoot, 0, $start+2).substr($repositoryRoot, $end+1);
	
	print "\nYou need to relocate your SVN root before performing a tag with this script.\n";
	print "\tE.g.  svn switch --relocate $repositoryRoot $newUrl\n";
	exit;
}

if ( -d $tagPath )
{
	print "Tag already exists.. you must specify a clean folder for the tag\n";
	exit;
}

print "Creating main branch ($sourceUrl)\n";
performCopy($sourceUrl,  $tagPath, 0, '');
print "\n";
validate($tagPath);


sub printDebugWithIndent
{
	#printWithIndent($_[0],"***DEBUG:".$_[1]);
}

sub validate
{
	my $destination = shift @_;
	printWithIndent(0,  "Validating - checking for externals ($destination)");
	$cmd = "svn propget svn:externals -R $destination";
	printDebugWithIndent(1,$cmd);
	
	my $externalsReport = `$cmd`;
	
	my @externals = split("\n", $externalsReport);
	my $count = @externals;
	
	if ($count ne 0)
	{
		print "*******FAILED***********  There are still some externals remaining\n";
		exit;
	}
}

# Perform an SVN copy on the supplied path
sub performCopy
{
	my $source = shift @_;
	my $destination = shift @_;
	my $indent = shift @_;
	my $repositoryRoot = shift @_;
	
	my $output='';

	printWithIndent($indent, "\tCopying $source to $destination");
	
	#If we have been asked to copy an absolute URL but we're not on the initial copy then we have a 'true' external in our externals list.... So do something special
	if ( (index($source, '^') eq -1) && ($indent != 0) )
	{
		printWithIndent($indent,"\tThis is an external source.... special handling");
		
		my $cmd = "svn export $source $destination";
		printDebugWithIndent($indent, $cmd);
	
		$output='';
		$output = `$cmd`;
		
		$cmd = "svn add $destination";
		printDebugWithIndent($indent, $cmd);
	
		$output .= `$cmd`;

	}
	else
	{
		#Strip out any username field that is hanging around
		my $strippedRepositoryRoot = $repositoryRoot;
		$strippedRepositoryRoot =~ s/\/\/(.)*\@/\/\//;

		#This converts a reference to a full URL
		$source =~ s/\^/$strippedRepositoryRoot/;
		

		my $cmd = "svn copy  --ignore-externals \"$source\" $destination";
		printDebugWithIndent($indent, $cmd);
	
		$output = `$cmd`;
	}	
	
	printWithIndent($indent,  "SVN Copy completed\n");
	printWithIndent($indent,  $output);
	printWithIndent($indent,  "*******\n");
	
	checkForAndCopyExternals($destination, $destination, $indent+1);
}


sub printDebug
{
	printDebugWithIndent(0, $_[0]);
}


sub printWithIndent
{
	my $indent = shift @_;
	
	while ($indent > 0)
	{
		print "  ";
		$indent--;
	}
	
	print "|".$_[0]."\n";
}

sub checkForAndCopyExternals
{
	my $source = shift @_;
	my $tagPath = shift @_;
	my $indent = shift @_;

	#rejig the path to remove things like './'
	$source =~ s/\.\///;
	
	my $repositoryRoot = getSvnInfo('Repository Root', $source);
	printWithIndent($indent, "...  source: $source    \t root:$repositoryRoot");
	
	printWithIndent($indent,  "Checking for externals ($source,$tagPath)");
	$cmd = "svn propget svn:externals -R $source";
	printDebugWithIndent($indent,$cmd);
	
	my $externalsReport = `$cmd`;
	
	
	my @externals = split("\n", $externalsReport);
	my $count = @externals;
	
	if ($count ne 0)
	{
		#remove external references
		printWithIndent($indent,  "Removing externals property from $source");
		$cmd = "svn propdel svn:externals  -R $source";
		printDebugWithIndent($indent,$cmd);
		`$cmd`;
	}

	
	my $ignore;
	my $rootFolder;
	my $firstLine = 1;
		
	my $hasExternals = 0;
	
	for my $line  (@externals)
	{
		if (trim($line) ne "")
		{
			printDebugWithIndent($indent,"line $line");
			
			my $externalName;
			my $externalUrl;
	
			#For the first line of a new folder, the propget is slightly different
#			if ($firstLine eq 1)
			if ( index($line, ' -' ) ne -1)
			{
				($rootFolder,$ignore, $externalUrl, $externalName) = split(' ', $line);
				printDebugWithIndent($indent,"Updated root folder");
				$firstLine = 0;
			}
			else
			{
				($externalUrl, $externalName) = split(' ', $line);
			}
	
			printWithIndent($indent,  "\tFound external under root folder: '$rootFolder'");
			printWithIndent($indent,  "\tName: $externalName");
			printWithIndent($indent,  "\tURL:  $externalUrl");
			$hasExternals = 1;
			
			#If the extern doesnt' contain a full URL then we need to map it
			
	
			#rejig the path to remove things like the current folder
			my $destinationPath = $rootFolder;

			#Puzzled, this was added for a reason, but now breaks the police tag....  Need to understand more..
			#$destinationPath =~ s/$source\///;
	
			printDebugWithIndent($indent,"tagPath=$tagPath");
			printDebugWithIndent($indent,"destinationPath=$destinationPath");
			printDebugWithIndent($indent,"externalName=$externalName");
		
			#Now copy the external source to the position that it use to be retrieved to
			performCopy($externalUrl, "$destinationPath/$externalName", $indent+1, $repositoryRoot);
		}
	}
	
}


sub getSvnInfo
{
	my $property = shift @_;
	my $source   = shift @_;
	
	printDebug($property);
	$cmd = "svn info $source";
	
	#Remove the need for Grep to simplify windows usage
	
	my $output = `$cmd`;
	my @lines = split("\n", $output);
	
	my $propertyValue = undef;
	
	foreach my $line (@lines) 
	{
		my ($key, $value) = split(': ', $line);
		
		if ($key eq $property)
		{
			$propertyValue = $value;
		}
	}
	

	if (!defined($propertyValue))	
	{
		print "Failed to find ($property) in ourput:\n$output\n\n";
		exit;
	}
	
	return $propertyValue;
}

sub printHelp
{
	print "Usage   make_tag.pl  --source [SOURCE_FOLDER] --tag [TAG_FOLDER]\n";
	print "\tE.g. ./trunk/Tools/make_tag.pl  --source ./trunk/  --tag ./tags/1.00\n";
}

sub trim
{
	my $string = shift @_;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}
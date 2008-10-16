#!/usr/local/bin/perl

use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
    NAME            => 'File::TabularData',
    VERSION_FROM    => 'lib/File/TabularData.pm',
    PREREQ_PM       => {
        'Archive::Zip' => '1.18',
        'File::BOM' => '0.09',
        'File::NFSLock' => '1.20',
        'IO::String' => '0',
        'Params::Validate' => '0.76',
        'Spreadsheet::ParseExcel' => '0.32',
        'Text::CSV_XS' => '0.34',
        'Test::Class' => '0.21',
        'Tie::IxHash' => '0',
        'XML::SAX' => '0.16'
    },
);

exit;

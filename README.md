# DITA-convert-hrefs-to-keyrefs

Converts `@href` cross-references to `@keyref` in topic files

## Introduction

In DITA, `@href` (file-based) cross-references refer to topics (or elements in them) by file:

```
<p>For more information, see <xref href="../chapter2/details.dita"/>.</p>
```

File-based cross-references are easy to create. However, if you reorganize the file/directory structure of your content, then you must update `@href` cross-references to reflect the new structure.

To avoid this, you can define _key values_ in your map by using the `@keys` attribute:

```
<bookmap>
  <title>My Book>
  <chapter href="chapter1/chapter1.dita"         keys="chapter1">
    <topicref href="chapter1/introduction.dita"  keys="introduction"/>
  </chapter>
  <chapter href="chapter2/chapter2.dita"         keys="chapter2">
    <topicref href="chapter2/details.dita"       keys="details"/>
  </chapter>
</bookmap>
```

then use `@keyref` (key-based) cross-references instead:

```
<p>For more information, see <xref keyref="details"/>.</p>
```

If you reorganize your content, the `@keys` values automatically redirect references to the new structure, and no cross-reference updates are needed.

The script provided in this repository allows you to convert your `href` cross-references to `keyref` automatically.

## How It Works

The script works as follows:

1. Collect and store all key definitions from the input map.
   * Convert each `@href` reference from a relative path to an absolute path.
   * Store each key/file pair.
   * Process submaps as needed.
2. Process each topic file referenced by the input map.
   * Find all `@href` references that contain `.dita`.
   * Convert the `@href` reference from a relative path to an absolute path.
   * If a referenced file matches a key/file pair, replace the `@href` with its matching `@keyref`.
   * If the topic file is modified, write it out.

`@href`/`@keyref` replacements are performed using regular-expression substitution so that the files are minimally modified. All existing formatting/indenting remains in place.

`@href` cross-references to nested subtopics are straightforward, as the file/subtopic ID path in the cross-reference `@href` matches the file/subtopic ID used in the map `@href`:

```
<topicref href="topic.dita" keys="topic">
  <topicref href="topic.dita#subtopic_id" keys="subtopic"/>
  <!--            ^^^^^^^^^^^^^^^^^^^^^^ topic/subtopic ID reference -->
</topicref>
```

```
<xref href="topic.dita#subtopic_id"/>
<!--        ^^^^^^^^^^^^^^^^^^^^^^ topic/subtopic ID reference -->
```

`@href` cross-references to non-topic elements are more complicated, as there is an additional non-topic element ID reference that does not appear in the map:

```
<xref href="topic.dita#subtopic_id/table_id"/>
<!--        ^^^^^^^^^^^^^^^^^^^^^^          topic/subtopic ID reference -->
<!--                              ^^^^^^^^^ nontopic element ID reference -->
```

To handle these cases, the script removes any nontopic element ID references before the comparison, then reapplies them after replacement as needed:

```
<xref keyref="subtopic/table_id"/>
```

## Getting Started

You can run this script in any typical perl-compliant environment. I am using an Ubuntu installation running on a Windows 10 machine via Windows Subsystem for Linux (WSL).

### Prerequisites

#### Perl

Before using this script, you must install the following perl modules:

```
sudo apt update
sudo apt install cpanminus
sudo cpanm install URI::Encode XML::Twig utf8::all
```

### Installing

Download or clone the repository, then put its `bin/` directory in your search path so that the `convert_hrefs_to_keyrefs.pl` utility is found in your search path.

For example, in the default bash shell, add this line to your `\~/.profile` file:

```
PATH=~/git/DITA-convert-hrefs-to-keyrefs/bin:$PATH
```

## Running the Utility

Run the script with `--help` to see the usage:

```
$ convert_hrefs_to_keyrefs.pl
Usage:
      [map1.ditamap [...]]
           DITA maps to process
      --dry-run
            Process but don't modify files
```

The script takes one or more map file names as input (wildcards are supported), then modifies their topic files in-place to convert `@href` cross-references to `@keyref`:

```
$ convert_hrefs_to_keyrefs.pl ./dita/*.ditamap
Updated 31 topics in 'dita/map1.ditamap'.
Updated 47 topics in 'dita/map2.ditamap'.
Updated 44 topics in 'dita/map3.ditamap'.
```

## Implementation Notes

The utility reads each topic file twice - once to obtain the root topic's `@id` value (to handle nontopic element references), then again to process the links. I considered various content-cache and read-on-demand tricks to avoid this, but in the end I went with code simplicity. With the aggressive filesystem caching in modern operating systems, the performance impact of reading a file twice is low (20-30% instead of 2X).

## Limitations

Note the following limitations of this script:

* This script requires that you already have `@keys` values defined in your map.
* Keyscopes inside maps (`scopename.keyname`) are not considered; only the leaf key value associated with a topic is considered.
* If a topic file is referenced multiple times within a map, the last-defined key for that file is used.
* The script processes each input map in turn. If multiple maps reference the same topic files, only the first referencing map notes the topics as updated (as they are already updated when subsequent maps are processed).

## Acknowledgments

This utility would not be possible without help from:

* [Synopsys Inc.](https://www.synopsys.com/) (my employer), for allowing me to share my work with the DITA community.

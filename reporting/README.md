chimera_find.sh
===============

`chimera_find.sh` creates a file listing of a directory in dCache.

This script is much faster than crawling through the dCache structure with client or API tools. The reason is that it queries the database directly, and it bypasses permissions. This makes it fast but you should be careful to not expose a project's file and directory names to unauthorized persons.

It was created by Gerd Behrman (according to: https://twiki.cern.ch/twiki/bin/view/AtlasComputing/DDMDarkDataAndLostFiles#Automated_checks_Site_Responsibi) and has been maintained and improved by others, of whom Christoph Anton Mitterer deserves a special mention.

The version here was forked from https://gitlab.cern.ch/atlas-adc-ddm-support/dark_data/blob/master/chimera_find.sh . There you can find the history.

I (Onno) created this fork because I don't have commit permissions in the CERN repo, and because dCache scripts are just better placed in a dCache repo.

The command's help text:

```
Usage: /usr/local/sbin/chimera_find.sh [-h HOSTNAME] [-p PORT] [-d DBNAME] [-U USERNAME] [-D DATE] [-l LIMIT] [-s] [-o] FILENAME [ROOT [PREFIX]]

Options:
  -h Specifies the host name of the machine on which postgresql is running. Defaults
     to connecting over a Unix-domain socket.
  -p Specifies the TCP port on which the postgresql server is listening for connections.
     Only used with -h. Defaults to 5432.
  -d Specifies the name of the database to connect to. Defaults to chimera.
  -U Connect to the database as the user username instead of the default.
  -D Specifies a cutoff date. Files created after this date are not included.
     Relative dates are allowed. Default is '1 day ago'.
  -l Specifies a limit on how many files to include. Mainly useful for testing.
  -s Include the size of each file in the dump.
  -c Include the creation date of each file in the dump.
  -x Include locality (O for online, N for nearline, can contain both)
  -o Order the dump by pathnames.

FILENAME is the output file name. Use “-” to output to STDOUT. ROOT is the root of the
directory tree to dump. ROOT defaults to /. PREFIX is a path PREFIX to place in front
of paths after ROOT has been striped off. Defaults to the value of ROOT.

Output is sorted unless a limit has been specified.
```

Here's an example of a cron job that creates a few dumps for the Atlas project. This example assumes `/pnfs` is a writable dCache NFS mount, and user `atlas` is the owner of the Atlas directory `/pnfs/grid.sara.nl/data/atlas`.

```
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

# m h dom m dow
# Please note that % needs to be escaped in a cron job definition!

0 12 28 * * root  DIR="/pnfs/grid.sara.nl/data/atlas/atlasdatadisk"    && DUMPFILE="$DIR/dumps/dump_$(date -d 'yesterday' '+\%Y\%m\%d')" && chimera_find.sh -U postgres "$DUMPFILE" "$DIR" / && chown atlas:atlas "$DUMPFILE" && chmod 640 "$DUMPFILE"
0 13 28 * * root  DIR="/pnfs/grid.sara.nl/data/atlas/atlasscratchdisk" && DUMPFILE="$DIR/dumps/dump_$(date -d 'yesterday' '+\%Y\%m\%d')" && chimera_find.sh -U postgres "$DUMPFILE" "$DIR" / && chown atlas:atlas "$DUMPFILE" && chmod 640 "$DUMPFILE"
```

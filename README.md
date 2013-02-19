MP3::InfoTag
============

This module contains functions for several tasks that occur while working with
ID3 tags of MP3 files.

The functions of this module work with a hash representing the ID3 tag, they do
not manipulate any files.
This module has a tight relationship to the MP3::Info module which uses the
same hash structure.
You'll need to read tags from files and write them to files; for these tasks
MP3::Info provides the necessary operations.

Thus you should regard this module as an extension that provides some functions
which might be useful when working with ID3 tags.



DEPENDENCIES

This module has no dependencies.



COPYRIGHT AND LICENCE

Copyright (C) 2005 Joachim Jautz

All rights reserved. This program is free software; you can redistribute it
and/or modify it under the terms of the Artistic License, distributed with
Perl.

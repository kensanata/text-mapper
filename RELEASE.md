# What to do for a release?

Run `make check`.

Update `Changes` with user-visible changes.

Check the copyright year in the `LICENSE`.

Double check the `MANIFEST`. Did we add new files that should be in
here?

```
perl Makefile.PL
make manifest
```

Increase the version in `lib/Game/TextMapper.pm`.

Commit any changes and tag the release.

Prepare an upload by using n.nn_nn for a developer release:

```
perl Makefile.PL
make distdir
mv Game-TextMapper-1.01 Game-TextMapper-1.01_01
tar czf Game-TextMapper-1.01_01.tar.gz Game-TextMapper-1.01_01
trash Game-TextMapper-1.01_01
cpan-upload -u SCHROEDER Game-TextMapper-1.01_01.tar.gz
```

If you’re happy with the results:

```
perl Makefile.PL && make && make dist
cpan-upload -u SCHROEDER Game-TextMapper-1.01.tar.gz
```

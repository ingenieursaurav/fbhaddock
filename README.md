# Haddock, a Haskell Documentation Tool


#### About haddock

This is Haddock, a tool for automatically generating documentation
from annotated Haskell source code.  It is primary intended for
documenting library interfaces, but it should be useful for any kind
of Haskell code.

Haddock lets you write documentation annotations next to the
definitions of functions and types in the source code, in a syntax
that is easy on the eye when writing the source code (no heavyweight
mark-up). The documentation generated by Haddock is fully hyperlinked
- click on a type name in a type signature to go straight to the
definition, and documentation, for that type.

Haddock understands Haskell's module system, so you can structure your
code however you like without worrying that internal structure will be
exposed in the generated documentation.  For example, it is common to
implement a library in several modules, but define the external API by
having a single module which re-exports parts of these implementation
modules.  Using Haddock, you can still write documentation annotations
next to the actual definitions of the functions and types in the
library, but the documentation annotations from the implementation
will be propagated to the external API when the documentation is
generated.  Abstract types and classes are handled correctly.  In
fact, even without any documentation annotations, Haddock can generate
useful documentation from your source code.


#### Documentation formats

Haddock can generate documentation in multiple formats; currently HTML
is implemented, and there is partial support for generating LaTeX and
Hoogle.


#### Source code documentation

Full documentation can be found in the doc/ subdirectory, in DocBook
format.


#### Contributing

Please create issues when you have any problems and pull requests if you have some code.

##### Hacking

To get started you'll need a latest GHC release installed.

Clone the repository:

```bash
  git clone https://github.com/haskell/haddock.git
  cd haddock
```

and then proceed using your favourite build tool.

###### Using Cabal sandboxes

```bash
cabal sandbox init
cabal sandbox add-source haddock-library
cabal sandbox add-source haddock-api
cabal sandbox add-source haddock-test
# adjust -j to the number of cores you want to use
cabal install -j4 --dependencies-only --enable-tests
cabal configure --enable-tests
cabal build -j4
# run the test suite
export HADDOCK_PATH="dist/build/haddock/haddock"
cabal test
```

###### Using Stack

```bash
stack init
stack install
# run the test suite
export HADDOCK_PATH="$HOME/.local/bin/haddock"
stack test
```


If you're a GHC developer and want to update Haddock to work with your
changes, you should be working on `ghc-head` branch instead of master.
See instructions at
https://ghc.haskell.org/trac/ghc/wiki/WorkingConventions/Git/Submodules
for an example workflow.

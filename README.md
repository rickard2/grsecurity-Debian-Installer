grsecurity source install script for Debian
=

What's this?
-

Installing the latest grsecurity enabled kernel from source can be a tedious task, and thus a great candidate for an install script. Lucky for us that I really enjoy making them. 

Most of the procedure is described when running the script, but in short terms this is what it does: 

1. Downloads the latest version of grsecurity and the matching kernel
2. Configures the kernel using the current kernel config
3. Compiles the kernel into a neat debian package using `make-kpkg`
4. Installs the debian package on the system

Hope you like it

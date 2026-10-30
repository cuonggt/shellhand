# Security

Shellhand connects to your machines, so a hole in it can matter more than a
crash does. If you have found one, please report it privately, not in a public
issue or discussion:
**[report a vulnerability](https://github.com/cuonggt/shellhand/security/advisories/new)**.
It stays between you and the maintainer until a fix is out.

## What to put in it

- What an attacker could do, and what they would need first: a host list
  someone sent you, a server you connect to, a file on a host you browse.
- The steps that show it, and the Shellhand and macOS versions. Shellhand ▸
  About Shellhand has the first.
- No real host names, addresses or keys. `web-1` and `203.0.113.5` show a
  problem as well as yours do.

## What counts

Anything in Shellhand itself. For example:

- the `ssh` command line it builds from your list or from what is typed into
  ⌘K, where a value could reach ssh as an option it was never meant to be;
- reading a host list: an imported `ssh_config`, CSV or YAML file, or the
  settings file;
- the SFTP window: where a transfer reads and writes, and how it carries links;
- the second login that reads a host's `/etc/os-release`, and what is done
  with the answer;
- updating: the feed, the signature check and the disk image.

A hole in OpenSSH belongs to [the OpenSSH project](https://www.openssh.com/security.html),
and one in macOS to [Apple](https://security.apple.com/).

## Versions

Only the latest release is fixed. A fix ships as a new release, which installed
copies pick up through their own updater, and the advisory is published once
that release is out — crediting you, unless you would rather not be named.

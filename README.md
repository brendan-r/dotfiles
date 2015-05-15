# Dotfiles

Currently, based very heavily on [Cătălin](https://github.com/alrra)’s dotfiles.

# TODO
You don't have two OS types, but rather two uses, desktop and server. The
server version should work on both Ubuntu desktop and server editions, just
install different programs. The general layout in the dotfiles program at the
moment is ideal.

You may even want a separate script (perhaps not in this repo), which does all
the server stuff (downloads the public keys, etc) that would usually happen on
aws.

`update_content.sh` is strangely named, and is really about github ssh keys.
You'd want to avoid that on the server version, and replace it with a version
that downloads your public key from somewhere.



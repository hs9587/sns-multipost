# Jotter investigation spikes

These scripts record browser experiments for the future Jotter poster. They are
not part of the production queue runner and may require the `ferrum` gem outside
the application's current bundle.

- `jotter_login.rb`: compare normal Chrome profile persistence with Ferrum
- `jotter_dom.rb`: inspect the composer DOM without collecting form values
- `jotter_form.rb`: inspect visibility, publication state, and textarea limits
- `jotter_open.rb`: test the in-app transition from Jots to the composer

The Jotter save-point URL is a credential. Supply it only through the local
`JOTTER_SAVEPOINT` environment variable. Never put the URL in source code,
command logs, screenshots, issues, or commits. Browser state is written below
the ignored `state/` directory.

Current stopping point: `jotter_open.rb` still treats the wallet link as a
ready signal, but that link also appears on the save-point processing page. The
next experiment must wait until the save-point URL is left or until the user
avatar changes, then identify a stable selector for the "メモを作成します"
trigger. No spike submits a post.

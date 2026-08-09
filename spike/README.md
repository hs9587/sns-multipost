# Jotter investigation spikes

These scripts record the browser experiments that led to the Jotter poster.
They are not part of the production queue runner. The production implementation
is `lib/jotter_browser.rb`; no spike submits a post.

- `jotter_login.rb`: compare normal Chrome profile persistence with Ferrum
- `jotter_dom.rb`: inspect the composer DOM without collecting form values
- `jotter_form.rb`: inspect visibility, publication state, and textarea limits
- `jotter_open.rb`: test the in-app transition from Jots to the composer

The Jotter save-point URL is a credential. Spikes accept it only through the
local `JOTTER_SAVEPOINT` environment variable. Production reads it from the
ignored `config.yml`. Never put the URL in source code, command logs,
screenshots, issues, or commits. Browser state is written below the ignored
`state/` directory.

The production solution launches plain Chrome for the save-point cryptographic
work, waits without CDP interaction, attaches Ferrum afterward, verifies the
configured account, explicitly selects public visibility, accepts the HTML
confirmation, and verifies the resulting public post URL.

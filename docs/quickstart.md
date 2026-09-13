# Quickstart

Open a log. Put the cursor on a request id and press `<leader>sK`: every other
occurrence lights up, in the whole buffer and in every window showing it.

`<leader>sk` — lowercase — does the narrower thing: only *this* occurrence,
pinned to this exact spot, for when the text is too common to light up
everywhere.

Point at a PID, press it again: a second color. An IP: a third. Then:

```
]k / [k          walk the occurrences of the token you are on
<leader>sL       the list: swatch, token, match count — pick one to jump to it
<leader>sq       every line matching any spotlight, into the quickfix list
<leader>sC       clear them all
```

Quit and come back tomorrow: they are still there.

Verify your setup any time with:

```vim
:checkhealth spotlight
```

See [what-you-get.md](what-you-get.md) for the rest of the surface at a
glance, or [commands.md](commands.md) for the full reference.

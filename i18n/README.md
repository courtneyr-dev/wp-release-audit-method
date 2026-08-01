# Internationalization, translation, and RTL

*WordPress runs in around 200 locales. Testing only in English tests a minority of installs.*

This is the dimension that gets skipped most, and it breaks in ways English-only testing structurally
cannot see: a layout that collapses in Arabic, a string that never loads because it was requested too
early, a date that reads as nonsense in Japanese.

It's also where a **single core change can break thousands of plugins at once** — which is exactly
the class of release breakage this project exists to catch.

---

## The worked example: WordPress 6.7

WordPress 6.7 changed translation loading to be **just-in-time** — translations load when a
translation function is actually called, rather than upfront. Calling `__()` or its siblings before
the `init` hook now triggers a `_doing_it_wrong()` notice.

Read [the dev note](https://make.wordpress.org/core/2024/10/21/i18n-improvements-6-7/) for the full
change. Two patterns that broke widely:

- **`get_plugin_data()` without `$translate = false`** — reading your own version number pulled in
  translation machinery before `init`.
- **Classes instantiated at file load with translation calls in the constructor** — extremely common,
  and completely invisible until 6.7.

The fix is to defer translation calls until `init` or later. And on WordPress 4.6+,
`load_plugin_textdomain()` **isn't necessary at all** for directory-hosted plugins — WordPress loads
translations automatically. If you still call it for older-version support or self-hosting, move it
to `init`.

> [!IMPORTANT]
> This is a textbook **"changed behavior, same name"** case from
> [the release-diff method](../plugin-theme-authors/release-diff-method.md#step-2--build-the-release-change-inventory).
> Nothing was removed. Nothing errored at first. The only warning was a dev note — and then a notice
> in everyone's logs at once.
>
> If you had grepped your surfaces for `load_plugin_textdomain`, `get_plugin_data`, and `__(` against
> that release's dev notes, you'd have found it in about a minute.

---

## Testing translation loading

**Turn debugging on and read the log.** `_doing_it_wrong()` notices for early translation are the
whole early-warning system here.

```php
define( 'WP_DEBUG', true );
define( 'WP_DEBUG_LOG', true );
```

**Switch the site to a non-English locale and exercise everything.**

```bash
wp language core install es_ES --activate
wp language plugin install my-plugin es_ES     # if translations exist
wp option get WPLANG
```

**Then read `debug.log` again.** Notices that only appear under a real locale are the ones you'd
otherwise ship blind — with `en_US` many translation paths never execute at all.

> [!TIP]
> **`en_US` is not a locale test.** WordPress short-circuits much of the translation machinery when
> the locale is English, so an English-only pass exercises the wrong code path. Install one real
> locale even if you never look at the words.

### What to check

| Check | Why |
|---|---|
| No `_doing_it_wrong` notices about early translation | The 6.7 class of breakage |
| Every user-facing string is wrapped | `__()`, `_e()`, `_n()`, `esc_html__()`, and friends |
| Your text domain matches your slug exactly | A mismatched domain means translations silently never load |
| Strings have translator comments where ambiguous | `/* translators: %s is a user name */` |
| Placeholders are numbered when reordering matters | `%1$s`, `%2$s` — word order differs by language |
| No concatenated sentences | `__( 'You have' ) . $n . __( 'items' )` is untranslatable |
| Dates and numbers use WordPress formatting | `date_i18n()`, `number_format_i18n()` |
| JavaScript strings are translated too | `wp_set_script_translations()` |

---

## RTL — right-to-left layout

Arabic, Hebrew, Persian, and Urdu read right to left. WordPress flips the admin automatically; **your
CSS is what breaks.**

```bash
wp language core install he_IL --activate    # Hebrew
wp language core install ar --activate       # Arabic
```

Then look at every screen you add. You're not reading the words — you're looking for layout that
didn't flip.

### What breaks, in order of likelihood

| Problem | Fix |
|---|---|
| `margin-left` / `padding-right` etc. hardcoded | Use CSS logical properties: `margin-inline-start`, `padding-inline-end` |
| `text-align: left` | `text-align: start` |
| `float: left` | `float: inline-start` |
| Icons and arrows pointing the wrong way | Flip with `[dir="rtl"]` rules or `transform: scaleX(-1)` |
| Absolute positioning with `left:` / `right:` | `inset-inline-start` / `inset-inline-end` |
| Shadows and gradients with a horizontal direction | Mirror them under `[dir="rtl"]` |
| A ship an `-rtl.css` that's stale | Regenerate it, or move to logical properties and delete it |

> [!TIP]
> **CSS logical properties remove most of this work permanently.** `margin-inline-start` is correct
> in both directions with no second stylesheet and no `[dir]` selectors. If you're writing new CSS,
> there's no reason to use `margin-left` again.

WordPress supports generating an RTL stylesheet via `wp_style_add_data( $handle, 'rtl', 'replace' )`,
and the `@wordpress/scripts` build can produce one. But logical properties are less to maintain.

### Other locale-driven layout issues

- **German and Finnish are long.** Buttons and labels that fit in English overflow. Test with a
  verbose locale, not just an RTL one.
- **Japanese, Chinese, and Korean have no spaces** between words in the same way — line breaking
  differs, and `word-break` assumptions fail.
- **Some locales change font stacks**, which shifts every measurement you assumed.

---

## For core release testing

Add these rows to a release sweep. They're cheap and almost nobody runs them:

- **Install a non-English locale and re-run your smoke pass.** Does the admin still work?
- **Install an RTL locale and look at the new screens** this release added. Every new UI is a new RTL
  risk.
- **Check the log for `_doing_it_wrong`** under a real locale.
- **Test the language switcher** — per-user language in Profile, and site language in Settings →
  General. They're separate code paths.
- **Multisite adds a third**: network default vs per-site vs per-user.

The [Polyglots team](https://make.wordpress.org/polyglots/) coordinates translation and is the right
place to report a string that can't be translated correctly — a missing translator comment or a
concatenated sentence is a real bug, filed on Trac against the **I18N** component.

---

## Tooling

| Tool | Use |
|---|---|
| [WP-CLI i18n commands](https://developer.wordpress.org/cli/commands/i18n/) | `wp i18n make-pot` extracts strings and warns about missing translator comments |
| [Plugin Check](https://wordpress.org/plugins/plugin-check/) | Flags unwrapped strings and text-domain mismatches |
| [translate.wordpress.org](https://translate.wordpress.org/) | Where directory-hosted translations live |
| [Theme Check](https://wordpress.org/plugins/theme-check/) | i18n rules for themes |

```bash
# Extract strings and surface i18n problems in one pass
wp i18n make-pot . languages/my-plugin.pot --debug
```

`--debug` is the useful part — it reports strings it couldn't extract and placeholders it thinks are
wrong.

---

## Checklist

```markdown
## i18n / RTL — WP <VERSION>

### Translation loading
- [ ] WP_DEBUG_LOG on, a real non-English locale installed and active
- [ ] No _doing_it_wrong notices about early translation
- [ ] Text domain matches the slug exactly
- [ ] get_plugin_data() calls pass $translate = false where appropriate
- [ ] No translation calls before init (constructors, file-level code)
- [ ] JS strings registered with wp_set_script_translations()

### Strings
- [ ] wp i18n make-pot --debug runs clean
- [ ] No concatenated sentences
- [ ] Numbered placeholders where word order can change
- [ ] Translator comments on anything ambiguous

### RTL
- [ ] Tested with an RTL locale active (he_IL or ar)
- [ ] Every screen this release added checked for layout that didn't flip
- [ ] Logical properties used, or the RTL stylesheet regenerated
- [ ] Directional icons flipped

### Locale edge cases
- [ ] A long-string locale (de_DE) doesn't overflow buttons or labels
- [ ] Dates and numbers use date_i18n() / number_format_i18n()
- [ ] Per-user language and site language both work
```

## Related

[Plugin & theme guide](../plugin-theme-authors/README.md) ·
[Release-diff method](../plugin-theme-authors/release-diff-method.md) ·
[Accessibility](../accessibility/) ·
[i18n handbook](https://developer.wordpress.org/plugins/internationalization/) ·
[Make/Polyglots](https://make.wordpress.org/polyglots/)

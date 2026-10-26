# GudaBags offline tests

Runs outside WoW. Nothing here is listed in `GudaBags.toc`, so the game never
loads it.

```
pip install luaparser lupa
python tests/run.py
```

Local only — there is no CI for these. If `python` opens the Microsoft Store,
that is the Windows app-execution alias, not a real interpreter: install one
(`winget install Python.Python.3.12`, or python.org), turn the alias off under
*Settings → Apps → Advanced app settings → App execution aliases*, then run the
`pip install` above.

## What it covers

**Syntax pass** — parses every `.lua` file in the addon. Catches the class of
error that otherwise only shows up as a silent addon-load failure in-game.

**Locale matrix** (`locale_matrix.lua`) — loads the addon's *real* rule code
(`Constants`, `Utils`, `DefaultCategories`, `RuleEngine`, `Core/Rules/*`,
`BagClassifier`) with the WoW API stubbed, then categorizes a fixed item set
three times: as an enUS, zhCN and deDE client.

The invariant under test: **`GetItemInfo` returns `itemType`/`itemSubType`
translated into the client's language, so categorization must never depend on
them.** Every item must land in the same category in all three locales.

It also asserts:

- `Constants.ITEM_CLASS` is derived correctly from `ITEM_CLASS_BY_NAME`
  (notably `"Trade Goods"` → `TRADE_GOODS`) with no collisions or dropped keys
- `ITEM_SUBCLASS_FISHING_POLE` keeps its `{classID, subClassID}` shape
- `GetItemClassLabel` survives an unknown classID without raising
- `BagClassifier` still types bags correctly after moving off `Enum.ItemClass`
- The Item Type dropdown localizes its **labels** while storing the canonical
  **English** value (so SavedVariables need no migration)
- `TOOL_WEAPON_SUBCLASS` is *derived* from probe items rather than hardcoded
- Tool detection stays correctly scoped: an unlisted tool is junk-**suppressed**
  (`IsToolLike`) without changing categorization (`IsProfessionTool`), and an
  ordinary gray dagger remains junk-eligible
- The font picker offers only fonts the client can actually render, with the
  client's own font first — a zhCN client must never be offered a Latin-only
  face, which would turn every string in the addon into boxes

**Search parser** (`search_parser.lua`) — parses real query strings
(`q>=rare`, `t:weapon`, `s:twohand`, quoted `tt:"..."` phrases, keywords, free
text) with the real `Core/SearchParser.lua` and matches them against
hand-built item records.

**Category manager** (`category_manager.lua`) — loads the real
`CategoryManager` and rule code and asserts:

- The saved-categories migration runs once per saved table, not on every
  `GetCategories()` call (it deep-copies all defaults)
- The category result cache never serves one character's verdict to another
  (an alt's copy of the same link answers BoE/junk/recent differently)
- Toggling `whiteItemsJunk` re-categorizes cached items
- "Name contains" / icon rules never throw on user text that is not a valid
  Lua pattern (`[`, `(13`), and valid patterns keep working

**Profile import** (`profile_import.lua`) — export → import round trip through
the real `Core/ProfileManager.lua`, and that hostile import strings (a huge
element count, absurd nesting, garbage) are rejected immediately instead of
freezing the client.

`stubs.lua` holds the WoW API stubs and loader these harnesses share.

## Regression check

To confirm a change actually fixes a locale bug rather than passing vacuously,
run the same harness against the previous revision:

```
git worktree add --detach /tmp/gudabags-base <ref>
GUDABAGS_PATH=/tmp/gudabags-base python tests/run.py
git worktree remove /tmp/gudabags-base
```

Before the locale fix, zhCN and deDE collapse nearly every item into
`Miscellaneous` while enUS passes — which is exactly the reported bug.

## Adding cases

Append to `ITEMS` in `locale_matrix.lua`. `classID`/`subClassID` must be the
real values the game returns; the localized `itemType`/`itemSubType` strings are
generated from `CLASS_NAMES` / `SUBCLASS_NAMES`.

Note the harness ignores each category's `enabled` flag: several built-ins are
class-gated (Quiver Bag = Hunter, Soul Bag = Warlock) and that gating is
orthogonal to locale behaviour.

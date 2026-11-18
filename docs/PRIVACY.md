# Privacy

What Pasto does with your data, as implemented in this repository. Paths in the last section point to the code
that backs each statement; if you change that code, update this page.

## In short

Pasto keeps what you copy **on your Mac**. It has no server, no account, no analytics, no telemetry and no
automatic crash reporting. It connects to the internet for three things only: link previews of the links you copy
(on by default, can be turned off), loading a link's page when you open its preview, and checking for updates.
Suggestions look at the window you are about to paste into, on the Mac, and never keep the image.

## What Pasto stores on your Mac

`<id>` is `jnjambrino.Pasto` (development builds use `jnjambrino.Pasto.dev` and keep everything apart).

| What | Where | For how long |
|---|---|---|
| **History and pinboards**: everything you copy (text, rich text, links, images, file references, colours), with the source app, the date and, for links, their title, icon and image | `~/Library/Application Support/<id>/` (`Pasto.sqlite` and its companion files) | The history, as long as *Settings › General › Keep history* says (a month by default; a day, a week, a year or unlimited). Pinned items and pinboards, until you delete them |
| **Search index**: each item's text (up to 5,000 characters), the text recognised in images, the source app, the type and the pinboard | The Mac's own Core Spotlight store, in an index named `<id>.search` | While the item exists; deleting an item (also by erasing the history or by expiry) removes it from the index |
| **Suggestions data**: which item was pasted into which app, what was suggested and chosen, the kind of destination field, and each item's class (text, address, code…). **Never the content you copied** | In Pasto's folder: `paste-journal.jsonl`, `item-classes.jsonl` and `Diagnostics/suggestion-log.jsonl` | Paste journal 90 days, suggestion log 30 days, the newest 5,000 item classes |
| **Text recognition queue**: identifiers of images waiting for text recognition | `SearchRecognitionQueue.txt` in Pasto's folder | Until each image is processed |
| **Settings** (shortcuts, ignored apps, welcome state, window sizes) | `~/Library/Preferences/<id>.plist` | Until removed |
| **Web page previews**: cache and cookies of the pages you open in a link's preview | `~/Library/WebKit/<id>`, `~/Library/Caches/<id>`, `~/Library/HTTPStorages/<id>` | Managed by WebKit, as in a browser |
| **Diagnostics**: launch records, crash and hang reports that macOS delivers to Pasto (MetricKit) and, only if you ask from *Help › Report a Problem…*, the session's log (without copied content: private values are written as `<private>`) | `Diagnostics/` in Pasto's folder | 30 days, at most 20 files of each kind |
| **Temporary image copies** for pasting or dragging images | `$TMPDIR/images/`, readable only by you | Deleted after 24 hours, at launch and on quit |
| **Updates** (Sparkle): the downloaded update and the date of the last check | `~/Library/Caches/<id>/` and `SU…` keys in the preferences | Until the next update |

Pasto's data folder is readable only by your user account (folders 0700, files 0600). There is no extra
encryption: the data is protected like the rest of your home folder (FileVault, if it is on), and Time Machine
backs it up with everything else.

## What leaves your Mac

Only this:

1. **Link previews** (on by default). When you copy a link, Pasto downloads that page itself to read its title,
   icon and image. It uses an ephemeral connection (no cookies, cache or credentials), reads the page only up to the
   end of its `<head>`, and refuses links and redirects that lead to local or private network addresses. For the
   website it is like a visit: it receives the request from your IP address. A single-use link (a sign-in or
   invitation link) can therefore be used up just by copying it.
   - Turn them off in *Settings › Privacy › Generate link previews*. When off, Pasto requests nothing when you copy
     a link.
2. **Opening a link's preview** (Space on a link card). The page loads inside Pasto as in a browser, with its
   cookies and cache. This only happens when you open the preview, whatever the link previews setting.
3. **Checking for updates** (Sparkle). Once a day, and whenever you choose *Check for Updates…*, Pasto reads the
   list of published versions at `https://pasto.jnjambrino.com/appcast.xml`; if there is a new one and you accept
   it, Pasto downloads it from `https://pasto.jnjambrino.com/downloads`. The request carries your IP address and, in
   its user agent, the versions of Pasto and Sparkle, like any web request. Pasto does not turn on Sparkle's system
   profile, which would send the Mac model and macOS version. Development builds never check for updates.

**Nothing else.** Pasto has no server or account of its own, does not send what you copy anywhere, has no
analytics, telemetry or automatic crash reports, and shares no data with anyone. *Help › Report a Problem…* only
opens a new email, or the contact page of the website, with the versions of Pasto and macOS and the Mac model
filled in: you send it yourself, and diagnostic files go only if you attach them. Actions you ask for (*Open*,
*Share*) do what they say, with the app you choose.

## What happens on the Mac and stays there

- **Suggestions** (*Settings › Intelligence*, on by default where available). Each time the panel opens, Pasto
  looks at the window of the app you are about to paste into to tell what kind of field it is (an address, a
  search box, code…) and order the suggestions.
  - It captures **that window only** (without the pointer), hands the image to Apple Intelligence's **on-device**
    model, and keeps only the answer: the kind of field. The image lives in memory for the duration of the
    question: **it is never saved, logged or sent anywhere**.
  - It only happens if suggestions are on, Apple Intelligence is available and enabled, and you have given Pasto
    the screen recording permission (asked the first time you use suggestions). It never happens while a password
    field has focus (secure input) or for apps you have told Pasto to ignore.
  - What is kept is the suggestions data in the table above, with no content.
- **Item classes** for suggestions: rules, and for text they cannot classify Apple Intelligence's on-device model,
  give each new item a class. Only the class is kept.
- **Text recognition in images**, with Vision, on the Mac, so you can search the text in screenshots. The words are
  kept only in the search index.
- **Search**: the index is on the Mac (Core Spotlight). Each item keeps its content only in Pasto's own custom
  attributes, which are not searchable by default, and has no standard title or text, so system-wide Spotlight
  (⌘Space) and Siri have nothing to find or show.

## What Pasto does not save

- What you copy in **password managers**: Apple Passwords, Keychain Access, 1Password, LastPass, Dashlane,
  Bitwarden, Enpass, RoboForm, Keeper and NordPass are ignored by default.
- Content that apps mark as **confidential** (passwords) or **transient** (put on the clipboard by the app without
  you copying anything), following the `org.nspasteboard` conventions. You can change this in *Settings › Privacy*.
- Anything you copy in the **apps you add** to *Settings › Privacy › Ignore applications*.
- Anything while Pasto is **paused** (from its menu, for 15 minutes up to 8 hours, or until you resume it).

The rules are checked from the pasteboard's types and the source app alone, **before** any content is read.

## Permissions Pasto asks for

| Permission (System Settings › Privacy & Security) | What for | Without it |
|---|---|---|
| **Paste from Other Apps** | Reading the clipboard each time you copy, which is what builds the history | Pasto cannot save what you copy |
| **Accessibility** | Pressing ⌘V for you, to paste the chosen item into the app you were using | Pasto only copies the item; you paste it yourself |
| **Screen & System Audio Recording** | Suggestions only: looking at the window you are about to paste into | Suggestions cannot tell the kind of field and are not shown |

*Open at login* also registers Pasto in *System Settings › General › Login Items*. With *Show during screen
sharing* turned off (*Settings › Privacy*), Pasto's windows are left out of shared screens, screenshots and
recordings.

## System log

Pasto writes operational messages to the macOS unified log under the subsystem `<id>`. **Copied content never
appears**, and the identifiers of source and destination apps, search queries and file paths are logged as private
values. These messages do not leave the Mac unless you share them (in a *sysdiagnose*, for example).

## Deleting your data

- **Erase the history**: *Settings › General › Erase History*. Deletes the history and removes its items from the
  search index; pinned items and pinboards stay. The suggestions data is deleted as well.
- **Remove everything**: *Settings › Privacy › Remove all data*. Moves Pasto's folders to the Trash (history,
  pinboards, suggestions data, diagnostics, caches and web preview data), empties the search index, deletes the
  settings, removes the login item and quits. Until you empty the Trash, the history can still be recovered. The
  privacy permissions stay in System Settings.
- **Uninstall by hand**:
  1. Quit Pasto (*Pasto › Quit Pasto*). To empty the search index too, erase the history before quitting.
  2. *System Settings › General › Login Items*: remove Pasto (or turn off *Open at login* before quitting).
  3. Drag `/Applications/Pasto.app` to the Trash.
  4. Delete `~/Library/Application Support/jnjambrino.Pasto`, `~/Library/Preferences/jnjambrino.Pasto.plist`,
     `~/Library/Caches/jnjambrino.Pasto`, `~/Library/WebKit/jnjambrino.Pasto` and
     `~/Library/HTTPStorages/jnjambrino.Pasto*`.
  5. To withdraw the permissions, in Terminal: `tccutil reset All jnjambrino.Pasto`.

## Where to check it in the code

Paths are relative to `Packages/PastoKit/Sources/`.

| Fact | Code |
|---|---|
| Capture rules, default ignored apps and types | `PastoCore/Capture/Rules/CaptureRules.swift`, `CaptureSettings.swift`, `PastoCore/Settings/PrivacySettings.swift` |
| Order of the pasteboard read (types and rules before data) | `PastoCore/Capture/Pasteboard/PasteboardReader.swift`, `SystemPasteboard.swift` |
| Link previews: setting, fetch, address checks | `PastoCore/Settings/PrivacySettings.swift` (`isLinkPreviewsEnabled`), `PastoCore/Capture/History/HistoryManager.swift` (`fetchMetadata`), `PastoCore/Capture/Links/` |
| The page in a link's preview | `PastoPreview/Content/LinkContentView.swift` |
| Suggestions: when the window is read and what happens to the image | `PastoPicks/Provider/PicksProvider.swift` (`panelDidShow`), `PastoPicks/Screen/ScreenContextReader.swift`, `PastoPicks/LanguageModel/` |
| Suggestions data and its retention | `PastoPicks/Provider/PicksProvider.swift` (`init`), `PastoPicks/PicksMetrics.swift`, `PastoPicks/Storage/` |
| Search index attributes | `PastoSearch/Index/SpotlightSearchIndex.swift`, `SearchIndexAttribute.swift` |
| Owner-only files, temporary images | `PastoFoundation/Files/OwnerOnlyAccess.swift`, `PastoCore/Restore/TemporaryImageDirectory.swift` |
| Remove all data | `PastoApp/DataRemoval.swift` |
| Updates | `PastoUpdates/`, `Config/Info.plist` and `Config/Release.xcconfig` at the repository root |
| The only network code | `PastoCore/Capture/Links/` (`URLSession`), `WKWebView` in `PastoPreview`, and Sparkle in `PastoUpdates` |

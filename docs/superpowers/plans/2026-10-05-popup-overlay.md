# Popup Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build one static web page that shows a centred confirmation dialog on a dimmed, see-through backdrop inside a transparent iOS `WKWebView`, and closes through the `closeWebviewWithResult` JS bridge.

**Architecture:** A single `index.html` holds the markup, styles and script. A zero-dependency test page loads it in iframes and checks behaviour and layout with mock bridges. A Swift file shows the host settings the page needs. The repository root is published with GitHub Pages.

**Tech Stack:** HTML, CSS and ES5 JavaScript (no build step, no dependencies); Swift with UIKit and WebKit for the example host; headless Chrome and `python3 -m http.server` to run the tests; `gh` for publishing.

**Spec:** `docs/superpowers/specs/2026-10-05-popup-overlay-design.md`

## Global Constraints

- One static `index.html` with inline CSS and JS. No build step, no dependencies, no external requests.
- Must work in `WKWebView` on iOS 13 and later: no `?.`, no `??`, no CSS `inset`, no flexbox `gap`, no `dvh`.
- Bridge payload is exactly `{ name: 'closeWebviewWithResult', result: <string> }`.
- Bridge order: Android first (`window.JSBridge.closeWebviewWithResult(JSON string)`), otherwise iOS (`window.webkit.messageHandlers.observer.postMessage(object)`).
- Results: OK sends `"ok"`. Cancel, a tap outside the card and Escape send `"cancel"`.
- Each popup sends at most one message.
- `html` and `body` backgrounds are transparent. The backdrop is `rgba(0, 0, 0, 0.4)`.
- Card: 24px side margins, 327px maximum width, 20px corner radius.
- Placeholders: English text, and the brand colour in the single CSS variable `--accent: #185FA5`.
- No `<meta name="color-scheme">`: the page styles every element itself, and the tag risks a painted canvas behind a transparent web view.
- The repository is public: no company names, product names or internal URLs in any file.

## Review Focus

Failure modes the spec implies but does not list as test cases. Each one is pinned by a test or a code path in the task named.

1. The host forgot to disable scrolling, so a drag rubber-bands the page: the page blocks `touchmove` itself (Task 1, test "Dragging does not scroll the page").
2. The page is opened in desktop Safari, where `window.webkit` exists but the `observer` handler does not: no error (Task 1, test "webkit without the observer handler").
3. An Android bridge exists but lacks the method: no error and no iOS call (Task 1, test "An Android bridge without the method").
4. A tap lands on the card padding or text, not on a button: nothing is sent (Task 1, test "A tap inside the card sends nothing").
5. The remote page returns HTTP 404 or the web process dies: the host closes and returns `"cancel"` (Task 2, navigation delegate methods; checked by compiling and by review, because it cannot run here).

## Tasks

### Task 1: Popup page and its tests

**Files:**
- Create: `tests/popup.test.html`
- Create: `tests/run.sh`
- Create: `index.html`

**Interfaces:**
- Consumes: nothing.
- Produces: `index.html` with these element ids, which the tests and the README rely on: `backdrop`, `card`, `popup-title`, `popup-message`, `btn-ok`, `btn-cancel`. On close it adds the class `closing` to `#backdrop`. It sends `{ name: 'closeWebviewWithResult', result: 'ok' | 'cancel' }`.

- [ ] **Step 1: Write the failing tests**

Create `tests/popup.test.html`:

````html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Popup overlay tests</title>
<style>
  body { font: 14px/1.5 -apple-system, BlinkMacSystemFont, sans-serif; margin: 16px; }
  #result { font-weight: 600; }
  .pass { color: #1B7F3B; }
  .fail { color: #B3261E; }
  #frames { position: absolute; left: -10000px; top: 0; }
  iframe { display: block; border: 0; }
</style>
</head>
<body>
<h1>Popup overlay tests</h1>
<p id="result">Running</p>
<ul id="log"></ul>
<div id="frames"></div>
<script>
var tests = [];
function test(name, fn) { tests.push({ name: name, fn: fn }); }

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function assertEqual(actual, expected, message) {
  var a = JSON.stringify(actual);
  var e = JSON.stringify(expected);
  if (a !== e) throw new Error(message + ': expected ' + e + ', got ' + a);
}

var frameCount = 0;

// Loads a fresh copy of the popup in an iframe of the given size.
function loadPopup(width, height) {
  return new Promise(function (resolve, reject) {
    var frame = document.createElement('iframe');
    frame.width = width || 375;
    frame.height = height || 667;
    frame.onload = function () {
      var win = frame.contentWindow;
      var doc = win.document;
      var popup = {
        win: win,
        doc: doc,
        backdrop: doc.getElementById('backdrop'),
        card: doc.getElementById('card'),
        title: doc.getElementById('popup-title'),
        message: doc.getElementById('popup-message'),
        ok: doc.getElementById('btn-ok'),
        cancel: doc.getElementById('btn-cancel'),
        errors: []
      };
      win.addEventListener('error', function (event) { popup.errors.push(event.message); });
      resolve(popup);
    };
    frame.onerror = reject;
    frame.src = '../index.html?run=' + (frameCount++);
    document.getElementById('frames').appendChild(frame);
  });
}

// Turns animations off so getBoundingClientRect is not affected by the entrance scale.
function freeze(popup) {
  var style = popup.doc.createElement('style');
  style.textContent = '*, *::before, *::after { animation: none !important; }';
  popup.doc.head.appendChild(style);
}

function mockIos(win) {
  var calls = [];
  Object.defineProperty(win, 'webkit', {
    configurable: true,
    value: { messageHandlers: { observer: { postMessage: function (body) { calls.push(body); } } } }
  });
  return calls;
}

function mockAndroid(win) {
  var calls = [];
  win.JSBridge = { closeWebviewWithResult: function (json) { calls.push(json); } };
  return calls;
}

function pressEscape(popup) {
  popup.doc.dispatchEvent(new popup.win.KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
}

var LONG_MESSAGE = new Array(60).join('This is a long message. ');

test('OK sends "ok" to the iOS handler exactly once', async function () {
  var p = await loadPopup();
  var calls = mockIos(p.win);
  p.ok.click();
  assertEqual(calls, [{ name: 'closeWebviewWithResult', result: 'ok' }], 'iOS messages');
});

test('Cancel sends "cancel"', async function () {
  var p = await loadPopup();
  var calls = mockIos(p.win);
  p.cancel.click();
  assertEqual(calls, [{ name: 'closeWebviewWithResult', result: 'cancel' }], 'iOS messages');
});

test('A tap on the backdrop sends "cancel"', async function () {
  var p = await loadPopup();
  var calls = mockIos(p.win);
  p.backdrop.click();
  assertEqual(calls, [{ name: 'closeWebviewWithResult', result: 'cancel' }], 'iOS messages');
});

test('A tap inside the card sends nothing', async function () {
  var p = await loadPopup();
  var calls = mockIos(p.win);
  p.card.click();
  p.title.click();
  p.message.click();
  assertEqual(calls, [], 'iOS messages');
});

test('Escape sends "cancel"', async function () {
  var p = await loadPopup();
  var calls = mockIos(p.win);
  pressEscape(p);
  assertEqual(calls, [{ name: 'closeWebviewWithResult', result: 'cancel' }], 'iOS messages');
});

test('Only the first action sends a message', async function () {
  var p = await loadPopup();
  var calls = mockIos(p.win);
  p.ok.click();
  p.ok.click();
  p.cancel.click();
  p.backdrop.click();
  pressEscape(p);
  assertEqual(calls, [{ name: 'closeWebviewWithResult', result: 'ok' }], 'iOS messages');
});

test('Android receives one JSON string and the iOS handler is skipped', async function () {
  var p = await loadPopup();
  var android = mockAndroid(p.win);
  var ios = mockIos(p.win);
  p.ok.click();
  assertEqual(android, ['{"name":"closeWebviewWithResult","result":"ok"}'], 'Android calls');
  assertEqual(ios, [], 'iOS messages');
});

test('An Android bridge without the method does not throw', async function () {
  var p = await loadPopup();
  p.win.JSBridge = {};
  var ios = mockIos(p.win);
  p.ok.click();
  assertEqual(p.errors, [], 'errors');
  assertEqual(ios, [], 'iOS messages');
});

test('A missing bridge does not throw and the popup still fades out', async function () {
  var p = await loadPopup();
  p.ok.click();
  assertEqual(p.errors, [], 'errors');
  assert(p.backdrop.classList.contains('closing'), 'backdrop has no closing class');
});

test('webkit without the observer handler does not throw', async function () {
  var p = await loadPopup();
  Object.defineProperty(p.win, 'webkit', { configurable: true, value: { messageHandlers: {} } });
  p.cancel.click();
  assertEqual(p.errors, [], 'errors');
});

test('window.bridge exists after closing and is not replaced', async function () {
  var first = await loadPopup();
  first.ok.click();
  assert(first.win.bridge !== null && typeof first.win.bridge === 'object', 'window.bridge was not created');

  var second = await loadPopup();
  second.win.bridge = { keep: 1 };
  second.ok.click();
  assertEqual(second.win.bridge.keep, 1, 'existing window.bridge');
});

test('The dialog is described for VoiceOver and takes focus', async function () {
  var p = await loadPopup();
  assertEqual(p.card.getAttribute('role'), 'alertdialog', 'role');
  assertEqual(p.card.getAttribute('aria-modal'), 'true', 'aria-modal');
  assertEqual(p.card.getAttribute('aria-labelledby'), 'popup-title', 'aria-labelledby');
  assertEqual(p.card.getAttribute('aria-describedby'), 'popup-message', 'aria-describedby');
  assert(p.title.textContent.trim().length > 0, 'title is empty');
  assert(p.message.textContent.trim().length > 0, 'message is empty');
  assertEqual(p.ok.tagName + '/' + p.cancel.tagName, 'BUTTON/BUTTON', 'button elements');
  assert(p.doc.activeElement === p.card, 'the card is not focused');
});

test('The page and the area outside the card are see-through', async function () {
  var p = await loadPopup();
  var style = function (element) { return p.win.getComputedStyle(element); };
  assertEqual(style(p.doc.documentElement).backgroundColor, 'rgba(0, 0, 0, 0)', 'html background');
  assertEqual(style(p.doc.body).backgroundColor, 'rgba(0, 0, 0, 0)', 'body background');
  assertEqual(style(p.backdrop).backgroundColor, 'rgba(0, 0, 0, 0.4)', 'backdrop background');
  assertEqual([p.backdrop.offsetWidth, p.backdrop.offsetHeight], [375, 667], 'backdrop size');
});

test('The card is centred with 24px margins on a 375px screen', async function () {
  var p = await loadPopup(375, 667);
  assertEqual(p.card.offsetWidth, 327, 'card width');
  assertEqual(p.card.offsetLeft, 24, 'left margin');
  var expectedTop = (667 - p.card.offsetHeight) / 2;
  assert(Math.abs(p.card.offsetTop - expectedTop) <= 1, 'card top is ' + p.card.offsetTop + ', expected ' + expectedTop);
});

test('The card narrows on a 320px screen', async function () {
  var p = await loadPopup(320, 568);
  assertEqual(p.card.offsetWidth, 272, 'card width');
  assertEqual(p.card.offsetLeft, 24, 'left margin');
});

test('The card stops at 327px on a wide screen', async function () {
  var p = await loadPopup(768, 1024);
  assertEqual(p.card.offsetWidth, 327, 'card width');
  assert(Math.abs(p.card.offsetLeft - (768 - 327) / 2) <= 1, 'card left is ' + p.card.offsetLeft);
});

test('Buttons sit side by side with equal width, Cancel on the left', async function () {
  var p = await loadPopup();
  freeze(p);
  var cancel = p.cancel.getBoundingClientRect();
  var ok = p.ok.getBoundingClientRect();
  assert(Math.abs(cancel.top - ok.top) <= 0.1, 'buttons are not on the same row');
  assert(cancel.left < ok.left, 'Cancel is not left of OK');
  assert(Math.abs(cancel.width - ok.width) <= 0.1, 'widths differ: ' + cancel.width + ' and ' + ok.width);
  assert(Math.abs(ok.left - cancel.right - 12) <= 0.1, 'space between buttons is ' + (ok.left - cancel.right));
  assert(cancel.height >= 48 && ok.height >= 48, 'buttons are shorter than 48px');
});

test('A label that does not fit stacks the buttons with OK on top', async function () {
  var p = await loadPopup();
  freeze(p);
  p.ok.textContent = 'Yes, continue with this request';
  var cancel = p.cancel.getBoundingClientRect();
  var ok = p.ok.getBoundingClientRect();
  var card = p.card.getBoundingClientRect();
  assert(ok.bottom <= cancel.top, 'OK is not above Cancel');
  assert(Math.abs(cancel.width - ok.width) <= 0.1, 'stacked widths differ');
  assert(ok.left >= card.left && ok.right <= card.right, 'OK overflows the card');
});

test('A long message scrolls inside the card and the buttons stay on screen', async function () {
  var p = await loadPopup(375, 420);
  freeze(p);
  p.message.textContent = LONG_MESSAGE;
  var card = p.card.getBoundingClientRect();
  var ok = p.ok.getBoundingClientRect();
  assert(card.top >= 23.5 && card.bottom <= 420 - 23.5, 'card spans ' + card.top + ' to ' + card.bottom);
  assert(p.message.scrollHeight > p.message.clientHeight, 'the message does not scroll');
  assert(ok.bottom <= card.bottom, 'buttons are pushed out of the card');
});

test('Dragging does not scroll the page, but a long message can scroll', async function () {
  var p = await loadPopup(375, 420);
  var dragIsBlocked = function (element) {
    var event = new p.win.Event('touchmove', { bubbles: true, cancelable: true });
    element.dispatchEvent(event);
    return event.defaultPrevented;
  };
  assertEqual(dragIsBlocked(p.backdrop), true, 'drag on the backdrop');
  assertEqual(dragIsBlocked(p.ok), true, 'drag on a button');
  assertEqual(dragIsBlocked(p.message), true, 'drag on a short message');
  p.message.textContent = LONG_MESSAGE;
  assertEqual(dragIsBlocked(p.message), false, 'drag on a long message');
});

test('The page avoids features newer than iOS 13', async function () {
  var response = await fetch('../index.html');
  assert(response.ok, 'index.html was not found');
  var source = await response.text();
  var banned = [
    [/\?\.[A-Za-z_$(\[]/, 'optional chaining'],
    [/\?\?/, 'nullish coalescing'],
    [/\binset\s*:/, 'CSS inset'],
    [/\d(dvh|svh|lvh)\b/, 'dynamic viewport units'],
    [/[;{\s]gap\s*:/, 'flexbox gap'],
    [/color-mix\(/, 'color-mix()'],
    [/:has\(/, ':has()'],
    [/name="color-scheme"/, 'the color-scheme meta tag']
  ];
  banned.forEach(function (rule) {
    assert(!rule[0].test(source), 'index.html uses ' + rule[1]);
  });
});

(async function run() {
  var log = document.getElementById('log');
  var passed = 0;
  for (var i = 0; i < tests.length; i++) {
    var item = document.createElement('li');
    try {
      await tests[i].fn();
      passed++;
      item.className = 'pass';
      item.textContent = 'PASS: ' + tests[i].name;
    } catch (error) {
      item.className = 'fail';
      item.textContent = 'FAIL: ' + tests[i].name + ' (' + error.message + ')';
    }
    log.appendChild(item);
  }
  document.getElementById('frames').innerHTML = '';
  var allPassed = passed === tests.length;
  var result = document.getElementById('result');
  result.className = allPassed ? 'pass' : 'fail';
  result.textContent = 'RESULT: ' + (allPassed ? 'PASS' : 'FAIL') + ' ' + passed + '/' + tests.length;
})();
</script>
</body>
</html>
````

Create `tests/run.sh`:

````bash
#!/bin/bash
# Runs tests/popup.test.html in headless Chrome and prints the result.
# Needs python3 and Google Chrome. Set CHROME to use another Chromium binary.
set -u
cd "$(dirname "$0")/.."

PORT="${PORT:-8123}"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"

python3 -m http.server "$PORT" >/dev/null 2>&1 &
SERVER=$!
trap 'kill "$SERVER" 2>/dev/null' EXIT

# Wait for the server to accept connections.
for _ in $(seq 1 100); do
  curl -s -o /dev/null "http://localhost:$PORT/" && break
  sleep 0.1
done

DOM=$("$CHROME" --headless=new --disable-gpu --virtual-time-budget=20000 \
  --dump-dom "http://localhost:$PORT/tests/popup.test.html" 2>/dev/null)

echo "$DOM" | grep -o 'FAIL: [^<]*'
RESULT=$(echo "$DOM" | grep -o 'RESULT: [A-Z]* [0-9]*/[0-9]*')
echo "${RESULT:-RESULT: FAIL (the test page did not finish)}"
[[ "$RESULT" == RESULT:\ PASS* ]]
````

Then make it executable:

```bash
chmod +x tests/run.sh
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh`
Expected: 21 `FAIL:` lines and `RESULT: FAIL 0/21`, because `index.html` does not exist yet.

- [ ] **Step 3: Write the popup page**

Create `index.html`:

````html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">
<meta name="format-detection" content="telephone=no">
<title>Confirm</title>
<style>
  /* Brand colour: change --accent only. */
  :root {
    --accent: #185FA5;
    --card: #FFFFFF;
    --title: #1A1A1A;
    --message: #5F6368;
    --cancel-bg: #EEEFF1;
    --cancel-fg: #1A1A1A;
    --backdrop: rgba(0, 0, 0, 0.4);
  }

  * {
    box-sizing: border-box;
    -webkit-tap-highlight-color: transparent;
  }

  html {
    height: 100%;
    background: transparent;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
    font-size: 17px;
    /* On iOS this follows the user's text size setting. Other browsers ignore it and keep 17px. */
    font: -apple-system-body;
    -webkit-text-size-adjust: 100%;
  }

  body {
    height: 100%;
    margin: 0;
    overflow: hidden;
    background: transparent;
    -webkit-user-select: none;
    user-select: none;
    -webkit-touch-callout: none;
    touch-action: manipulation;
  }

  .backdrop {
    position: fixed;
    top: 0;
    right: 0;
    bottom: 0;
    left: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 24px;
    padding: calc(24px + env(safe-area-inset-top)) calc(24px + env(safe-area-inset-right)) calc(24px + env(safe-area-inset-bottom)) calc(24px + env(safe-area-inset-left));
    background: var(--backdrop);
    /* iOS only sends taps to elements it treats as clickable. */
    cursor: pointer;
    animation: backdrop-in 200ms ease-out both;
  }

  .backdrop.closing {
    pointer-events: none;
    animation: backdrop-out 150ms ease-in both;
  }

  .card {
    display: flex;
    flex-direction: column;
    width: 100%;
    max-width: 327px;
    max-height: 100%;
    padding: 24px 20px 20px;
    border-radius: 20px;
    background: var(--card);
    box-shadow: 0 12px 40px rgba(0, 0, 0, 0.18);
    text-align: center;
    cursor: default;
    outline: none;
    animation: card-in 200ms ease-out both;
  }

  .icon {
    position: relative;
    display: flex;
    flex: none;
    align-items: center;
    justify-content: center;
    width: 48px;
    height: 48px;
    margin: 0 auto 12px;
    color: var(--accent);
  }

  /* A light tint of the accent colour behind the icon. */
  .icon::before {
    content: "";
    position: absolute;
    top: 0;
    right: 0;
    bottom: 0;
    left: 0;
    border-radius: 50%;
    background: var(--accent);
    opacity: 0.12;
  }

  .icon svg {
    position: relative;
    width: 26px;
    height: 26px;
  }

  .title {
    flex: none;
    margin: 0;
    font-size: 1.0588rem;
    font-weight: 600;
    line-height: 1.3;
    color: var(--title);
  }

  /* Scrolls inside the card when large text makes the card taller than the screen. */
  .message {
    flex: 0 1 auto;
    min-height: 0;
    margin: 8px 0 0;
    overflow-y: auto;
    -webkit-overflow-scrolling: touch;
    font-size: 0.8824rem;
    line-height: 1.5;
    color: var(--message);
  }

  /* Margins give the 12px space between buttons. wrap-reverse puts OK on top when a label does not fit. */
  .actions {
    display: flex;
    flex: none;
    flex-wrap: wrap-reverse;
    margin: 20px -6px -12px;
  }

  .btn {
    flex: 1 0 calc(50% - 12.5px);
    min-height: 48px;
    margin: 0 6px 12px;
    padding: 10px 12px;
    border: 0;
    border-radius: 12px;
    font: inherit;
    font-size: 0.9412rem;
    font-weight: 600;
    white-space: nowrap;
    cursor: pointer;
    -webkit-appearance: none;
    appearance: none;
    transition: opacity 120ms ease-out, transform 120ms ease-out;
  }

  .btn-cancel {
    background: var(--cancel-bg);
    color: var(--cancel-fg);
  }

  .btn-ok {
    background: var(--accent);
    color: #FFFFFF;
  }

  .btn:active {
    opacity: 0.7;
    transform: scale(0.98);
  }

  .btn:focus-visible {
    outline: 2px solid var(--accent);
    outline-offset: 2px;
  }

  @keyframes backdrop-in {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  @keyframes backdrop-out {
    from { opacity: 1; }
    to { opacity: 0; }
  }

  @keyframes card-in {
    from { transform: scale(0.94); }
    to { transform: scale(1); }
  }

  @media (prefers-color-scheme: dark) {
    :root {
      --card: #2A2B2F;
      --title: #FFFFFF;
      --message: #B4B6BB;
      --cancel-bg: #3A3B40;
      --cancel-fg: #FFFFFF;
    }

    .icon {
      color: #FFFFFF;
    }

    .icon::before {
      opacity: 1;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .card {
      animation: none;
    }
  }
</style>
</head>
<body>
  <div class="backdrop" id="backdrop">
    <div class="card" id="card" role="alertdialog" aria-modal="true" aria-labelledby="popup-title" aria-describedby="popup-message" tabindex="-1">
      <!-- Optional icon: delete this block to remove it. -->
      <div class="icon" aria-hidden="true">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3"/>
          <path d="M12 17h.01"/>
        </svg>
      </div>
      <!-- Text: edit the title, message and button labels here. -->
      <h1 class="title" id="popup-title">Confirm your request</h1>
      <p class="message" id="popup-message">Do you want to continue? You can't undo this later.</p>
      <div class="actions">
        <button type="button" class="btn btn-cancel" id="btn-cancel">Cancel</button>
        <button type="button" class="btn btn-ok" id="btn-ok">OK</button>
      </div>
    </div>
  </div>
<script>
(function () {
  'use strict';

  var RESULT_OK = 'ok';
  var RESULT_CANCEL = 'cancel';

  function closeWebviewWithResult(result) {
    var obj = {
      name: 'closeWebviewWithResult',
      result: result
    };

    if (!window.bridge) {
      window.bridge = {};
    }

    if (window.JSBridge) {
      // android
      if (typeof window.JSBridge.closeWebviewWithResult === 'function') {
        window.JSBridge.closeWebviewWithResult(JSON.stringify(obj));
      }
    } else if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.observer) {
      // ios
      window.webkit.messageHandlers.observer.postMessage(obj);
    } else {
      // No native bridge, for example a desktop browser.
      console.log('[PopupOverlay] closeWebviewWithResult', obj);
    }
  }

  var backdrop = document.getElementById('backdrop');
  var card = document.getElementById('card');
  var message = document.getElementById('popup-message');
  var closed = false;

  // Sends the result once, then fades out. Later taps do nothing.
  function close(result) {
    if (closed) {
      return;
    }
    closed = true;
    closeWebviewWithResult(result);
    backdrop.className += ' closing';
  }

  document.getElementById('btn-ok').addEventListener('click', function () {
    close(RESULT_OK);
  });

  document.getElementById('btn-cancel').addEventListener('click', function () {
    close(RESULT_CANCEL);
  });

  // Only a tap on the backdrop itself counts as "outside", not a tap inside the card.
  backdrop.addEventListener('click', function (event) {
    if (event.target === backdrop) {
      close(RESULT_CANCEL);
    }
  });

  document.addEventListener('keydown', function (event) {
    if (event.key === 'Escape' || event.keyCode === 27) {
      close(RESULT_CANCEL);
    }
  });

  // Stop the page from rubber-banding when dragged. A message that overflows may still scroll.
  document.addEventListener('touchmove', function (event) {
    var messageScrolls = message.scrollHeight > message.clientHeight;
    if (!(messageScrolls && message.contains(event.target))) {
      event.preventDefault();
    }
  }, { passive: false });

  // iOS only applies :active styles when a touch listener exists.
  document.addEventListener('touchstart', function () {}, { passive: true });

  card.focus();
})();
</script>
</body>
</html>
````

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh`
Expected: no `FAIL:` lines and `RESULT: PASS 21/21`.

- [ ] **Step 5: Commit**

```bash
git add index.html tests/popup.test.html tests/run.sh
git commit -m "feat: add confirmation popup page with tests"
```

### Task 2: Example iOS host

**Files:**
- Create: `ios/PopupOverlayViewController.swift`

**Interfaces:**
- Consumes: the message `{ name: 'closeWebviewWithResult', result: String }` posted to the `observer` handler by `index.html` (Task 1).
- Produces: `PopupOverlayViewController(source:onResult:)`, with `Source.remote(URL)` and `Source.bundled(fileURL: URL, readAccess: URL)`. `onResult` receives `"ok"` or `"cancel"` after the controller is dismissed. The README (Task 3) shows this API.

- [ ] **Step 1: Write the check that fails**

There is no unit-test target for this example file, so the check is that it compiles for iOS 13 with no warnings, in Swift 5 and Swift 6 language modes. Use `xcrun swiftc`, not a bare `swiftc`, so the Xcode toolchain is used.

Run:

```bash
xcrun --sdk iphonesimulator swiftc -typecheck -warnings-as-errors -swift-version 5 \
  -target arm64-apple-ios13.0-simulator ios/PopupOverlayViewController.swift
```

Expected: FAIL with "no such file or directory", because the file does not exist yet.

- [ ] **Step 2: Write the example host**

Create `ios/PopupOverlayViewController.swift`:

````swift
import UIKit
import WebKit

/// Example host for the popup overlay page.
///
/// Shows a transparent, full-screen web view on top of the current screen, loads the
/// popup page, and returns the result the page sends through `closeWebviewWithResult`.
///
///     let url = URL(string: "https://misternay.github.io/popup-overlay/")!
///     let popup = PopupOverlayViewController(source: .remote(url)) { result in
///         print(result) // "ok" or "cancel"
///     }
///     present(popup, animated: false) // the page animates itself in
public final class PopupOverlayViewController: UIViewController {

    public enum Source {
        /// A page hosted on a server.
        case remote(URL)
        /// A copy of `index.html` inside the app. `readAccess` is the folder that contains it.
        case bundled(fileURL: URL, readAccess: URL)
    }

    private static let messageHandlerName = "observer"
    private static let closeCommand = "closeWebviewWithResult"
    private static let cancelResult = "cancel"

    private let source: Source
    private var onResult: ((String) -> Void)?
    private var webView: WKWebView?

    public init(source: Source, onResult: @escaping (String) -> Void) {
        self.source = source
        self.onResult = onResult
        super.init(nibName: nil, bundle: nil)
        // Keep the presenting screen in place behind the web view.
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        // VoiceOver should not read the screen behind the popup.
        view.accessibilityViewIsModal = true

        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(WeakScriptMessageHandler(self), name: Self.messageHandlerName)

        let webView = WKWebView(frame: view.bounds, configuration: configuration)
        webView.navigationDelegate = self

        // Transparency. Without these the area outside the card is white.
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        if #available(iOS 15.0, *) {
            webView.underPageBackgroundColor = .clear
        }

        // The page never scrolls. Stop the rubber-band bounce and the safe-area insets.
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        // Pin to the screen edges, not the safe area, so the dim covers the whole screen.
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        self.webView = webView

        switch source {
        case .remote(let url):
            webView.load(URLRequest(url: url))
        case .bundled(let fileURL, let readAccess):
            webView.loadFileURL(fileURL, allowingReadAccessTo: readAccess)
        }
    }

    /// Closes the popup and reports the result once. Later calls do nothing.
    private func finish(with result: String) {
        guard let onResult = onResult else { return }
        self.onResult = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: Self.messageHandlerName)

        guard presentingViewController != nil else {
            onResult(result)
            return
        }
        dismiss(animated: true) {
            onResult(result)
        }
    }
}

// MARK: - Messages from the page

extension PopupOverlayViewController: WKScriptMessageHandler {
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.messageHandlerName,
              let body = message.body as? [String: Any],
              body["name"] as? String == Self.closeCommand else { return }
        finish(with: body["result"] as? String ?? Self.cancelResult)
    }
}

// MARK: - Load failures

// If the page cannot be shown, close. Otherwise an invisible web view would block the app.
extension PopupOverlayViewController: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.isForMainFrame,
           let response = navigationResponse.response as? HTTPURLResponse,
           response.statusCode >= 400 {
            decisionHandler(.cancel)
            finish(with: Self.cancelResult)
            return
        }
        decisionHandler(.allow)
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(with: Self.cancelResult)
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(with: Self.cancelResult)
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(with: Self.cancelResult)
    }
}

// MARK: - Weak message handler

/// `WKUserContentController` keeps its handler alive. This wrapper avoids a retain cycle.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
````

- [ ] **Step 3: Run the check to verify it passes**

Run both:

```bash
xcrun --sdk iphonesimulator swiftc -typecheck -warnings-as-errors -swift-version 5 \
  -target arm64-apple-ios13.0-simulator ios/PopupOverlayViewController.swift
xcrun --sdk iphonesimulator swiftc -typecheck -warnings-as-errors -swift-version 6 \
  -target arm64-apple-ios13.0-simulator ios/PopupOverlayViewController.swift
```

Expected: both print nothing and exit with status 0. If the SDK declares a delegate method differently, change only that signature to match the SDK and note the change.

- [ ] **Step 4: Commit**

```bash
git add ios/PopupOverlayViewController.swift
git commit -m "feat: add example iOS host for the popup"
```

### Task 3: README

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: element markers and constants in `index.html` (Task 1): the comments `<!-- Text: ... -->` and `<!-- Optional icon: ... -->`, the CSS variable `--accent`, the constants `RESULT_OK` and `RESULT_CANCEL`. The API `PopupOverlayViewController(source:onResult:)` (Task 2). The test command `bash tests/run.sh` (Task 1).
- Produces: nothing other tasks use.

- [ ] **Step 1: Write the README**

Create `README.md`:

`````markdown
# Popup Overlay

A single web page that shows a centred confirmation dialog on a dimmed, see-through
backdrop. It is made to be loaded in a transparent, full-screen `WKWebView` on top of
a native iOS screen, so the native screen stays visible around the dialog.

Live page: https://misternay.github.io/popup-overlay/

## How it works

- The page background is transparent. Only the dim layer and the card are drawn.
- OK, Cancel, a tap outside the card and the Escape key each close the popup.
- Closing calls the native JS bridge once. The app then closes the web view.

## Bridge contract

The page sends one message and expects nothing back.

| User action | `result` |
|---|---|
| Tap OK | `"ok"` |
| Tap Cancel | `"cancel"` |
| Tap outside the card | `"cancel"` |
| Press Escape | `"cancel"` |

On iOS the page posts an object to the `observer` message handler:

```js
window.webkit.messageHandlers.observer.postMessage({
  name: 'closeWebviewWithResult',
  result: 'ok'
});
```

On Android it passes the same payload as one JSON string:

```js
window.JSBridge.closeWebviewWithResult('{"name":"closeWebviewWithResult","result":"ok"}');
```

If `window.JSBridge` exists the page uses Android and skips iOS. With no bridge, for
example in a desktop browser, it logs the payload to the console.

## Change the text and colour

Everything is in `index.html`:

- **Text:** edit the title, message and button labels in the block marked
  `<!-- Text: ... -->`.
- **Icon:** delete the block marked `<!-- Optional icon: ... -->` to remove it.
- **Colour:** change `--accent` at the top of the `<style>` block.
- **Result values:** change `RESULT_OK` and `RESULT_CANCEL` at the top of the script.

## iOS host

The area outside the card is only see-through when the web view itself is transparent.
`ios/PopupOverlayViewController.swift` is a working example. These settings matter:

```swift
webView.isOpaque = false
webView.backgroundColor = .clear
webView.scrollView.backgroundColor = .clear
webView.scrollView.isScrollEnabled = false
webView.scrollView.bounces = false
webView.scrollView.contentInsetAdjustmentBehavior = .never
```

Also:

- Present the view controller with `.overFullScreen`, so the screen behind stays visible.
- Pin the web view to the screen edges, not to the safe area.
- If the page fails to load, close the web view. Otherwise an invisible view blocks the app.

Using the example:

```swift
let url = URL(string: "https://misternay.github.io/popup-overlay/")!
let popup = PopupOverlayViewController(source: .remote(url)) { result in
    print(result) // "ok" or "cancel"
}
present(popup, animated: false) // the page animates itself in
```

To load a copy bundled in the app instead, add `index.html` to the app target and use:

```swift
let file = Bundle.main.url(forResource: "index", withExtension: "html")!
let popup = PopupOverlayViewController(
    source: .bundled(fileURL: file, readAccess: file.deletingLastPathComponent())
) { result in
    print(result)
}
```

## Test

Run the browser tests from the repository root. This needs `python3` and Google Chrome:

```bash
bash tests/run.sh
```

Expected output: `RESULT: PASS 21/21`.

You can also open the test page in any browser:
https://misternay.github.io/popup-overlay/tests/popup.test.html

The tests cannot check the real app. On a simulator or a device, check that:

- the native screen is visible and dimmed around the card, including under the status
  bar and the home indicator
- there is no white flash when the popup opens
- nothing scrolls, bounces or zooms
- OK returns `"ok"`, and Cancel and a tap outside return `"cancel"`
- the card looks right in dark mode and at the largest text size

## Requirements

iOS 13 or later. No build step and no dependencies.
`````

- [ ] **Step 2: Check the README against the other files**

Run:

```bash
grep -c "Text: edit the title" index.html
grep -c "Optional icon: delete this block" index.html
grep -c "RESULT_OK\|RESULT_CANCEL" index.html
grep -c "case bundled(fileURL: URL, readAccess: URL)" ios/PopupOverlayViewController.swift
```

Expected: `1`, `1`, a number of 4 or more, and `1`. Each thing the README tells the reader to edit exists.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add README with bridge contract and host setup"
```

### Task 4: Publish to GitHub and GitHub Pages

**Files:**
- No new files. `.nojekyll` already exists so GitHub Pages serves the files as they are.

**Interfaces:**
- Consumes: the committed repository on branch `main`.
- Produces: the public repository `misternay/popup-overlay` and the site `https://misternay.github.io/popup-overlay/`.

- [ ] **Step 1: Create the public repository and push**

```bash
gh repo create misternay/popup-overlay --public --source=. --remote=origin --push \
  --description "Centred confirmation popup for a transparent WKWebView overlay"
```

Expected: the repository URL is printed and `main` is pushed.

- [ ] **Step 2: Turn on GitHub Pages for the root of `main`**

```bash
gh api -X POST repos/misternay/popup-overlay/pages -f "source[branch]=main" -f "source[path]=/"
```

Expected: JSON that contains `"html_url":"https://misternay.github.io/popup-overlay/"`.

- [ ] **Step 3: Wait for the Pages build and check the live page**

```bash
gh run watch --repo misternay/popup-overlay --exit-status \
  "$(gh run list --repo misternay/popup-overlay --limit 1 --json databaseId --jq '.[0].databaseId')"
curl -s -o /dev/null -w "%{http_code}\n" https://misternay.github.io/popup-overlay/
curl -s https://misternay.github.io/popup-overlay/ | grep -c 'id="btn-ok"'
```

Expected: the run succeeds, then `200` and `1`.

- [ ] **Step 4: Check the live page in a browser**

Open `https://misternay.github.io/popup-overlay/tests/popup.test.html` and confirm it shows `RESULT: PASS 21/21`. Open `https://misternay.github.io/popup-overlay/` at a phone-sized viewport in light and dark mode and confirm the card is centred on a dimmed backdrop.

## Execution

A multi-agent workflow runs this plan: one build agent for Task 1 and one for Tasks 2 and 3, then independent reviewers with separate lenses (transparent `WKWebView` behaviour, iOS 13 web compatibility and touch handling, bridge contract and spec coverage), each finding checked by a second agent before it is acted on. Task 4 runs in the main session.

# Security policy

Pasto sees everything you copy, so security reports are taken seriously and handled before anything else.

## Supported versions

Only the latest release receives fixes. Pasto updates itself (Sparkle checks once a day), so a fix ships as a new
version rather than as a patch to an older one.

| Version | Supported |
|---|---|
| 1.0.x, latest | Yes |
| Anything older | No: update from the app's menu, *Check for Updates…* |

## Reporting a vulnerability

Please **do not open a public issue** for a security problem.

Report it privately, by either:

- GitHub's private vulnerability reporting: [Report a vulnerability](https://github.com/jnjambrin0/Pasto/security/advisories/new), or
- email to **hello@jnjambrino.com** with "Security" in the subject.

Include what you found, the Pasto version (*Pasto › About Pasto*), the macOS version, and the steps to reproduce
it. A proof of concept helps, but never send real clipboard contents or personal data: describe them instead.

What to expect:

- an acknowledgement within a few days;
- an assessment and, if the report is confirmed, a plan and a rough date for the fix;
- credit in the release notes once the fix is out, unless you prefer to stay anonymous.

Please give a reasonable time to ship a fix before disclosing the problem publicly.

## Scope

In scope: the Pasto app as distributed from [pasto.jnjambrino.com](https://pasto.jnjambrino.com) and the GitHub
releases, the update feed and its signatures, and the code in this repository.

Examples of what matters most here: clipboard contents leaving the Mac, content reaching logs, the search index
or files readable by other users, ignored apps or concealed content being captured anyway, updates that could be
tampered with, and ways for another process to drive Pasto into pasting something.

Out of scope: problems that need an attacker who already controls your user account, and issues in macOS or in
third-party software (please report those to their authors; for Sparkle, see its own security policy).

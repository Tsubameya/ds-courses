# Directeur Sportif — course index

Data read by the Directeur Sportif cycling app: for an event of its calendar, where the bike course can be found.

- `index.json` — one entry per event.
- `courses/` — the course files we host.

## Two kinds of course

**Official** — the organiser's own GPX file. It is *not* hosted here: the index only records its exact address on the
organiser's site, with the size and SHA-256 seen on the day it was checked. The app downloads it from the organiser.

**Interpreted** — a course we traced from the organiser's published map, because no GPX file was available. It is an
aid for preparing a ride, **not an official document**: it can differ from the real course, and the organiser's
information always prevails. Every such file says so in its name, "(interpreted)", and the app labels it the same way.

Each entry carries `source`, the organiser's page the course comes from, and `checked`, the date we last looked at it.

## Organisers

If you organise one of these events and want a course corrected or removed, open an issue on this repository. It will
be removed on request.

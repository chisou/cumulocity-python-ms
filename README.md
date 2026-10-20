# Cumulocity Python Microservice Template

A template for building Cumulocity microservices in Python, using [FastAPI](https://fastapi.tiangolo.com)
and [pyc8y](https://github.com/chisou/cumulocity-python-sdk). It comes with several examples (single-tenant,
multi-tenant, Notification 2.0 subscriptions, and a structured one with background tasks) and `just` commands to register, run, build and deploy the microservice.

## Getting started

You need [uv](https://docs.astral.sh/uv/), [just](https://just.systems) and
[Docker](https://www.docker.com) with `buildx`. On Apple Silicon, Docker also needs amd64
emulation (see the prerequisites in [.template/README.md](.template/README.md)).

1. Create your own repository from this template, either with the **Use this template** button
   on GitHub or with the GitHub CLI:

   ```sh
   gh repo create my-microservice --template chisou/cumulocity-python-ms --private --clone
   cd my-microservice
   ```

   Not using GitHub? Clone this repository, then delete the `.git` folder and run `git init`.

2. Turn the template into your project:

   ```sh
   just init
   ```

   This asks for a name, provider, description, which example to start from, the
   isolation (`MULTI_TENANT` or `PER_TENANT`) and a license. The example, isolation and license are
   picked from a menu with the arrow keys (or `j`/`k`) and Enter. You can also give some or
   all of them as options, and are then only asked for the rest (see `just init --help`):

   ```sh
   just init --name my-microservice --provider "ACME Corp" --license MIT
   ```

   It then:

   - writes `MICROSERVICE_NAME`, `PROVIDER` and `ISOLATION`,
   - moves the chosen example's files into `src/app/` (so `src/app/main.py` is your service) and removes the others,
   - updates name, description, author and license classifier in `pyproject.toml`,
   - writes `LICENSE`, `README.md` and a fresh `CHANGELOG.md`,
   - removes the template-only files in `.template/`.

3. Check the `[project.urls]` in `pyproject.toml`, then commit and push.

Your new `README.md` explains how to register, run, build and deploy the microservice.

## Working on the template

The template itself is a runnable project: `src/app/main.py` only imports the `app` of one
example, so `just register`, `just serve`, `just build` and `just deploy` work as described
in [.template/README.md](.template/README.md). Change that import to try another example, e.g.
`from app.simple_tenant.main import app`.

Every folder in `src/app` is an example that `just init` offers. It contains a `main.py`
that creates the `app`, an `__init__.py`, and a `README.md` whose first line (a `# ` heading)
is the description shown to the user. Examples import their own modules absolutely, e.g.
`from app.advanced.state import AppState`. To add an example, add such a folder.

`just init` moves the chosen example's files up into `src/app/` and rewrites `app.<example>`
in the imports to `app`, so the project looks like it was never an example.

Files in `.template/` are only used by `just init`, which deletes the folder when done:

- `init.sh` is the script behind `just init`.
- `test-init.sh` tests `init.sh` (see below).
- `README.md` is the project README, with `{NAME}` and `{DESCRIPTION}` placeholders.
- `licenses/` holds the license texts, with `{YEAR}`, `{PROVIDER}` and `{DESCRIPTION}` placeholders.

`just init` refuses to run when `.template/` is missing, i.e. when the project
has already been initialized.

### Testing `just init`

Running `just init` changes the repository it runs in, so don't run it in the template
itself. Use `test-init.sh` instead: it runs `just init` on a temporary copy of the
template and checks the result.

```sh
.template/test-init.sh                                     # advanced, MULTI_TENANT, ASL2
.template/test-init.sh -e simple_tenant -i PER_TENANT -l MIT
```

Run `.template/test-init.sh --help` for all options.

It copies all files git knows about (including uncommitted changes, but not ignored
files like `.venv` or `.env`), runs `just init` with all values given as options, and
checks that:

- invalid microservice names are rejected before any file is changed,
- `.template/` was removed,
- the chosen example was moved up into `src/app` (imports rewritten, other examples and
  READMEs gone) and can be imported,
- `MICROSERVICE_NAME`, `ISOLATION` and the name in `pyproject.toml` are set,
- `LICENSE` contains the provider and no placeholders are left in `LICENSE` or `README.md`,
- `CHANGELOG.md` was written,
- a second `just init` is refused.

It prints `OK` and removes the temporary folder on success. On failure it names the
failed check and keeps the folder so you can look at the result. To test all
examples, run it in a loop:

```sh
for e in advanced multi_tenant multi_tenant_n20 simple_tenant; do .template/test-init.sh -e $e; done
```

To see what users see, run it with `--interactive` (`-I`). You then answer the questions
yourself; nothing is checked, and the generated project is kept so you can look at it.
Options you give are passed on, so you're only asked for the rest:

```sh
.template/test-init.sh --interactive
.template/test-init.sh --interactive --license MIT
```

The test only checks the files `init` writes. It doesn't check whether the
generated microservice actually runs.

If you run `just init` in the template by accident, `git checkout . && git clean -fd`
restores it. Note that `git clean` also deletes all other untracked files.

## License

Apache License 2.0, see [LICENSE](LICENSE).

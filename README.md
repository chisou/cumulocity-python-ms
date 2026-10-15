# Cumulocity Python Microservice Template

A template for building Cumulocity microservices in Python, using [FastAPI](https://fastapi.tiangolo.com)
and [pyc8y](https://github.com/chisou/cumulocity-python-sdk). It comes with a multi-tenant and a
single-tenant example and `just` commands to register, run, build and deploy the microservice.

## Getting started

You need [uv](https://docs.astral.sh/uv/), [just](https://just.systems) and
[Docker](https://www.docker.com) with `buildx`.

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
   isolation (`MULTI_TENANT` or `PER_TENANT`) and a license. It then:

   - writes `MICROSERVICE_NAME`, `PROVIDER` and `ISOLATION`,
   - keeps the chosen example as `src/main/main.py` and removes the others,
   - updates name, description, author and license classifier in `pyproject.toml`,
   - writes `LICENSE`, `README.md` and a fresh `CHANGELOG.md`,
   - removes the template-only files in `.template/`.

3. Check the `[project.urls]` in `pyproject.toml`, then commit and push.

Your new `README.md` explains how to register, run, build and deploy the microservice.

## Working on the template

The template itself is a runnable project: `src/main/main.py` imports the multi-tenant
example, so `just register`, `just serve`, `just build` and `just deploy` work as described
in [.template/README.md](.template/README.md). Change it to import `simple_tenant`
to try the single-tenant example.

Every file in `src/main` except `main.py` is an example that `just init` offers. The file
name without `.py` is its name, and its first line (a comment) is the description shown
to the user. To add an example, add a file there and start it with a one-line comment.

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
.template/test-init.sh                                # multi_tenant, MULTI_TENANT, ASL2
.template/test-init.sh simple_tenant PER_TENANT MIT   # example, isolation, license
```

It copies all files git knows about (including uncommitted changes, but not ignored
files like `.venv` or `.env`), answers the questions with fixed values, and checks that:

- `.template/` was removed,
- `src/main` only contains `main.py`, and it is the chosen example,
- `MICROSERVICE_NAME`, `ISOLATION` and the name in `pyproject.toml` are set,
- `LICENSE` contains the provider and no placeholders are left in `LICENSE` or `README.md`,
- `CHANGELOG.md` was written,
- a second `just init` is refused.

It prints `OK` and removes the temporary folder on success. On failure it names the
failed check and keeps the folder so you can look at the result. To test all
examples, run it in a loop:

```sh
for e in multi_tenant simple_tenant; do .template/test-init.sh $e; done
```

To see what users see, run it with `-i`. You then answer the questions yourself; nothing
is checked, and the generated project is kept so you can look at it:

```sh
.template/test-init.sh -i
```

The test only checks the files `init` writes. It doesn't check whether the
generated microservice actually runs.

If you run `just init` in the template by accident, `git checkout . && git clean -fd`
restores it. Note that `git clean` also deletes all other untracked files.

## License

Apache License 2.0, see [LICENSE](LICENSE).

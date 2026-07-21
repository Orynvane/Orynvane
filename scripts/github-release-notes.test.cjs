"use strict";

const assert = require("node:assert/strict");
const { afterEach, test } = require("node:test");
const { generateNotes } = require("./github-release-notes.cjs");

const originalFetch = global.fetch;

afterEach(() => {
  global.fetch = originalFetch;
});

function context(overrides = {}) {
  return {
    env: {
      GITHUB_API_URL: "https://api.github.test/",
      GITHUB_REPOSITORY: "Orynvane/Orynvane",
      GITHUB_TOKEN: "test-token",
    },
    lastRelease: { gitTag: "v0.1.2" },
    logger: { log() {} },
    nextRelease: {
      gitHead: "5f914889f4ad75f65a895095675b2424f2183d99",
      gitTag: "v0.2.0",
    },
    ...overrides,
  };
}

test("uses GitHub's generated release notes for the semantic-release tag", async () => {
  const requests = [];
  const expectedNotes = "## What's Changed\n* Add native playback by @culpen90";
  global.fetch = async (url, options) => {
    requests.push({ url, options });
    return {
      ok: true,
      async json() {
        return { body: expectedNotes, name: "v0.2.0" };
      },
    };
  };

  const notes = await generateNotes({}, context());

  assert.equal(notes, expectedNotes);
  assert.equal(requests.length, 1);
  assert.equal(
    requests[0].url,
    "https://api.github.test/repos/Orynvane/Orynvane/releases/generate-notes",
  );
  assert.equal(requests[0].options.method, "POST");
  assert.equal(requests[0].options.headers.Authorization, "Bearer test-token");
  assert.deepEqual(JSON.parse(requests[0].options.body), {
    previous_tag_name: "v0.1.2",
    tag_name: "v0.2.0",
    target_commitish: "5f914889f4ad75f65a895095675b2424f2183d99",
  });
});

test("requires the GitHub Actions repository context", async () => {
  await assert.rejects(
    generateNotes(
      {},
      context({
        env: { GITHUB_TOKEN: "test-token" },
      }),
    ),
    /GITHUB_REPOSITORY/,
  );
});

test("fails the release when GitHub cannot generate the notes", async () => {
  global.fetch = async () => ({
    ok: false,
    status: 422,
    statusText: "Unprocessable Entity",
    async text() {
      return "invalid tag target";
    },
  });

  await assert.rejects(
    generateNotes({}, context()),
    /GitHub could not generate release notes \(422 Unprocessable Entity\): invalid tag target/,
  );
});

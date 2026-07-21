"use strict";

const DEFAULT_GITHUB_API_URL = "https://api.github.com";

async function generateNotes(_pluginConfig, context) {
  const { env, lastRelease, logger, nextRelease } = context;
  const token = env.GH_TOKEN || env.GITHUB_TOKEN;
  const repository = env.GITHUB_REPOSITORY;

  if (!token) {
    throw new Error(
      "GITHUB_TOKEN or GH_TOKEN is required to generate GitHub release notes",
    );
  }

  if (!repository || !/^[^/]+\/[^/]+$/.test(repository)) {
    throw new Error(
      "GITHUB_REPOSITORY must identify the release repository as owner/name",
    );
  }

  const apiUrl = (env.GITHUB_API_URL || DEFAULT_GITHUB_API_URL).replace(
    /\/+$/,
    "",
  );
  const payload = {
    tag_name: nextRelease.gitTag,
    // The tag is created after generateNotes runs, so GitHub needs its target.
    target_commitish: nextRelease.gitHead,
  };

  if (lastRelease.gitTag) {
    payload.previous_tag_name = lastRelease.gitTag;
  }

  const response = await fetch(
    `${apiUrl}/repos/${repository}/releases/generate-notes`,
    {
      method: "POST",
      headers: {
        Accept: "application/vnd.github+json",
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
        "User-Agent": "Orynvane-semantic-release",
        "X-GitHub-Api-Version": "2022-11-28",
      },
      body: JSON.stringify(payload),
    },
  );

  if (!response.ok) {
    const detail = await response.text();
    throw new Error(
      `GitHub could not generate release notes (${response.status} ${response.statusText})${detail ? `: ${detail}` : ""}`,
    );
  }

  const releaseNotes = await response.json();
  if (typeof releaseNotes.body !== "string") {
    throw new Error("GitHub returned release notes without a body");
  }

  logger.log("Generated GitHub release notes for %s", nextRelease.gitTag);
  return releaseNotes.body;
}

module.exports = { generateNotes };

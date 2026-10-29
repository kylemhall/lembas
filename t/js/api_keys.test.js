"use strict";

const { beforeEach, describe, test } = require("node:test");
const assert = require("node:assert/strict");
const browser = require("./browser.js");

const { apiKeys, toastStore } = browser.Lembas;

beforeEach(() => browser.reset());

const key = {
    id: 7,
    label: "Deploy",
    key_prefix: "lmb_abcdefgh",
    created_at: "2026-10-01T00:00:00Z",
};

describe("apiKeys", () => {
    test("the keys of the user", async () => {
        const keys = apiKeys();
        browser.respond(200, { api_keys: [key] });
        await keys.init();
        assert.equal(browser.requests[0].url, "/api/v1/api_keys");
        assert.deepEqual(keys.keys, [key]);
    });

    test("an error while loading", async () => {
        browser.respond(401, { errors: [{ message: "Not signed in" }] });
        await apiKeys().load();
        assert.equal(toastStore.message, "Not signed in");
    });

    test("a new key, shown once", async () => {
        const keys = apiKeys();
        keys.label = "Deploy";
        browser.respond(201, { ...key, key: "lmb_secret" });
        browser.respond(200, { api_keys: [key] });
        await keys.create();
        assert.equal(browser.requests[0].method, "POST");
        assert.deepEqual(browser.requests[0].body, { label: "Deploy" });
        assert.equal(keys.created.key, "lmb_secret");
        assert.equal(keys.label, "");
        assert.deepEqual(keys.keys, [key], "the list is loaded again");
        assert.equal(keys.busy, false);

        await keys.copy();
        assert.deepEqual(browser.copied, ["lmb_secret"]);
        keys.dismiss();
        assert.equal(keys.created, null, "and gone");
    });

    test("a key that cannot be made", async () => {
        const keys = apiKeys();
        browser.respond(400, {
            errors: [{ message: "Expected string - got null." }],
        });
        await keys.create();
        assert.equal(toastStore.message, "Expected string - got null.");
        assert.equal(keys.created, null);
        assert.equal(keys.busy, false);
    });

    test("revoke", async () => {
        const keys = apiKeys();
        browser.confirm = false;
        await keys.revoke(key);
        assert.deepEqual(browser.confirmations, [
            'Revoke the key "Deploy"? Scripts that use it will stop working.',
        ]);
        assert.equal(browser.requests.length, 0, "not without a confirmation");

        browser.confirm = true;
        browser.respond(204);
        browser.respond(200, { api_keys: [] });
        await keys.revoke(key);
        assert.equal(browser.requests[0].method, "DELETE");
        assert.equal(browser.requests[0].url, "/api/v1/api_keys/7");
        assert.equal(toastStore.message, "Revoked Deploy");
        assert.deepEqual(keys.keys, []);
    });

    test("a key that cannot be revoked", async () => {
        browser.respond(404, { errors: [{ message: "No such API key" }] });
        await apiKeys().revoke(key);
        assert.equal(toastStore.message, "No such API key");
    });
});

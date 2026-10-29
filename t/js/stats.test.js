"use strict";

const { beforeEach, describe, test } = require("node:test");
const assert = require("node:assert/strict");
const browser = require("./browser.js");

const { linkStats } = browser.Lembas;

beforeEach(() => browser.reset());

function day(offset) {
    return new Date(Date.now() - offset * 86400000).toISOString().slice(0, 10);
}

function page(ending) {
    const component = linkStats();
    component.$root = { dataset: { ending } };
    return component;
}

const link = {
    ending: "a b",
    short_url: "https://s.example/a",
    long_url: "https://example.org/",
    clicks: 9,
};
const stats = {
    total: 3,
    clicks_per_day: [
        { day: day(1), clicks: 1 },
        { day: day(0), clicks: 2 },
    ],
    top_referers: [{ host: "chat.example", clicks: 3 }],
};

describe("linkStats", () => {
    test("before the stats come", () => {
        const stats = page("a");
        assert.deepEqual(stats.perDay, []);
        assert.deepEqual(stats.referers, []);
        assert.equal(stats.total, 0);
        assert.equal(
            stats.maxClicks,
            1,
            "never zero: it is the maximum of the bars"
        );
    });

    test("the last 30 days", async () => {
        const component = page("a b");
        browser.respond(200, link);
        browser.respond(200, stats);
        await component.init();
        assert.equal(component.ending, "a b");
        assert.equal(browser.requests[0].url, "/api/v1/links/a%20b");
        assert.equal(
            browser.requests[1].url,
            `/api/v1/links/a%20b/stats?from=${day(29)}&to=${day(0)}`
        );
        assert.deepEqual(component.link, link);
        assert.equal(component.total, 3);
        assert.deepEqual(component.perDay, stats.clicks_per_day);
        assert.deepEqual(component.referers, stats.top_referers);
        assert.equal(component.maxClicks, 2);
        assert.equal(component.error, "");
    });

    test("another period", async () => {
        const component = page("a");
        component.error = "an old error";
        browser.respond(200, link);
        browser.respond(200, stats);
        await component.setRange(7);
        assert.equal(component.days, 7);
        assert.match(
            browser.requests[1].url,
            new RegExp(`from=${day(6)}&to=${day(0)}$`)
        );
        assert.equal(component.error, "", "the error is gone");
    });

    test("someone else's link", async () => {
        const component = page("a");
        browser.respond(403, {
            errors: [{ message: "This link belongs to someone else" }],
        });
        browser.respond(403, {
            errors: [{ message: "This link belongs to someone else" }],
        });
        await component.init();
        assert.equal(component.error, "This link belongs to someone else");
        assert.equal(component.link, null);
    });
});

"use strict";

const { beforeEach, describe, test } = require("node:test");
const assert = require("node:assert/strict");
const browser = require("./browser.js");

const { api, copyText, linkList, shortener, toastStore } = browser.Lembas;

beforeEach(() => browser.reset());

function link(ending, fields) {
    return {
        ending,
        short_url: "https://s.example/" + ending,
        long_url: "https://example.org/" + ending,
        ...fields,
    };
}

describe("register", () => {
    test("the toast and the components", () => {
        assert.equal(browser.stores.toast, toastStore);
        assert.equal(browser.components.shortener, shortener);
        assert.equal(browser.components.linkList, linkList);
        assert.equal(browser.components.linkStats, browser.Lembas.linkStats);
        assert.equal(browser.components.apiKeys, browser.Lembas.apiKeys);
    });
});

describe("api", () => {
    test("a request without a body", async () => {
        browser.respond(200, { name: "Jane" });
        assert.deepEqual(await api("GET", "/me"), {
            status: 200,
            data: { name: "Jane" },
        });
        const [request] = browser.requests;
        assert.equal(request.url, "/api/v1/me");
        assert.equal(request.method, "GET");
        assert.equal(request.credentials, "same-origin");
        assert.deepEqual(request.headers, { Accept: "application/json" });
        assert.equal(request.body, undefined);
    });

    test("a body is sent as JSON", async () => {
        browser.respond(201, { ending: "abc" });
        await api("POST", "/links", { long_url: "https://example.org/" });
        const [request] = browser.requests;
        assert.equal(request.headers["Content-Type"], "application/json");
        assert.deepEqual(request.body, { long_url: "https://example.org/" });
    });

    test("204 has no body", async () => {
        browser.respond(204);
        assert.deepEqual(await api("DELETE", "/links/abc"), {
            status: 204,
            data: null,
        });
    });

    test("an error: the message of the error document", async () => {
        browser.respond(409, {
            errors: [{ message: '"abc" is already taken' }],
        });
        await assert.rejects(api("POST", "/links", {}), {
            message: '"abc" is already taken',
        });
    });

    test("an error without JSON: the status", async () => {
        browser.respond(502);
        await assert.rejects(api("GET", "/me"), { message: "Status 502" });
    });

    test("an error with other JSON: the status", async () => {
        browser.respond(500, { unexpected: true });
        await assert.rejects(api("GET", "/me"), { message: "Status 500" });
    });
});

describe("toast", () => {
    test("shown, then cleared after 4 seconds", t => {
        t.mock.timers.enable({ apis: ["setTimeout"] });
        toastStore.show("Saved", "success");
        assert.equal(toastStore.message, "Saved");
        assert.equal(toastStore.kind, "success");
        t.mock.timers.tick(3999);
        toastStore.show("Broken", "error");
        t.mock.timers.tick(3999);
        assert.equal(
            toastStore.message,
            "Broken",
            "a new message waits 4 seconds again"
        );
        assert.equal(toastStore.kind, "error");
        t.mock.timers.tick(1);
        assert.equal(toastStore.message, "");
    });
});

describe("copyText", () => {
    test("copied", async () => {
        await copyText("https://s.example/abc");
        assert.deepEqual(browser.copied, ["https://s.example/abc"]);
        assert.equal(toastStore.message, "Copied https://s.example/abc");
    });

    test("the browser refuses", async () => {
        browser.clipboardFails = true;
        await copyText("https://s.example/abc");
        assert.equal(
            toastStore.message,
            "Could not copy, select the link instead"
        );
        assert.equal(toastStore.kind, "error");
    });
});

describe("shortener", () => {
    test("a new link, with a custom ending", async () => {
        const form = shortener();
        form.longUrl = "https://example.org/page";
        form.ending = "mine";
        browser.respond(201, link("mine"));
        await form.submit();
        assert.deepEqual(browser.requests[0].body, {
            long_url: "https://example.org/page",
            ending: "mine",
        });
        assert.equal(form.result.short_url, "https://s.example/mine");
        assert.equal(form.note, "New link");
        assert.equal(form.longUrl, "");
        assert.equal(form.ending, "");
        assert.equal(form.busy, false);
        assert.deepEqual(browser.events, ["lembas:link-created"]);
    });

    test("a link the user already had", async () => {
        const form = shortener();
        form.longUrl = "https://example.org/page";
        browser.respond(200, link("abc123"));
        await form.submit();
        assert.deepEqual(browser.requests[0].body, {
            long_url: "https://example.org/page",
        });
        assert.equal(form.note, "You already had a link for this URL");
    });

    test("an error", async () => {
        const form = shortener();
        form.result = link("old");
        browser.respond(400, {
            errors: [{ message: "The long URL must be an http or https URL" }],
        });
        await form.submit();
        assert.equal(form.error, "The long URL must be an http or https URL");
        assert.equal(form.result, null);
        assert.equal(form.busy, false);
        assert.deepEqual(browser.events, []);
    });

    test("copy", async () => {
        const form = shortener();
        form.result = link("abc");
        await form.copy();
        assert.deepEqual(browser.copied, ["https://s.example/abc"]);
    });
});

describe("linkList", () => {
    function list(all) {
        const component = linkList();
        component.$root = { dataset: { all } };
        return component;
    }

    test("the links of the user", async () => {
        const links = list("0");
        assert.equal(links.empty, false, "not empty while it loads");
        browser.respond(200, { links: [link("a")], total: 1 });
        await links.init();
        assert.equal(links.all, false);
        assert.equal(
            browser.requests[0].url,
            "/api/v1/links?page=1&per_page=25"
        );
        assert.deepEqual(links.links, [link("a")]);
        assert.equal(links.total, 1);
        assert.equal(links.loading, false);
        assert.equal(links.empty, false);
        assert.equal(links.pages, 1);
    });

    test("everybody's links, for an admin", async () => {
        const links = list("1");
        browser.respond(200, { links: [], total: 0 });
        await links.init();
        assert.equal(links.all, true);
        assert.equal(
            browser.requests[0].url,
            "/api/v1/links?page=1&per_page=25&all=true"
        );
        assert.equal(links.empty, true);
        assert.equal(links.pages, 1, "one page, even empty");
    });

    test("search and pages", async () => {
        const links = list("0");
        links.page = 3;
        links.q = "docs";
        browser.respond(200, { links: [], total: 60 });
        await links.search();
        assert.equal(
            browser.requests[0].url,
            "/api/v1/links?page=1&per_page=25&q=docs"
        );
        assert.equal(links.pages, 3);
        browser.respond(200, { links: [], total: 60 });
        await links.next();
        assert.equal(links.page, 2);
        browser.respond(200, { links: [], total: 60 });
        await links.prev();
        assert.equal(links.page, 1);
        assert.equal(browser.requests.length, 3);
    });

    test("an error while loading", async () => {
        const links = list("0");
        browser.respond(500);
        await links.load();
        assert.equal(toastStore.message, "Status 500");
        assert.equal(toastStore.kind, "error");
        assert.equal(links.loading, false);
    });

    test("edit a long URL", async () => {
        const links = list("0");
        links.links = [link("a"), link("b")];
        links.startEdit(links.links[1]);
        assert.equal(links.editing, "b");
        assert.equal(links.editUrl, "https://example.org/b");
        links.cancelEdit();
        assert.equal(links.editing, null);

        links.startEdit(links.links[1]);
        links.editUrl = "https://example.org/new";
        browser.respond(
            200,
            link("b", { long_url: "https://example.org/new" })
        );
        await links.saveEdit();
        assert.equal(browser.requests[0].method, "PATCH");
        assert.equal(browser.requests[0].url, "/api/v1/links/b");
        assert.deepEqual(browser.requests[0].body, {
            long_url: "https://example.org/new",
        });
        assert.equal(links.links[1].long_url, "https://example.org/new");
        assert.equal(
            links.links[0].long_url,
            "https://example.org/a",
            "the others are left alone"
        );
        assert.equal(links.editing, null);
        assert.equal(toastStore.message, "Saved");
    });

    test("disable and enable", async () => {
        const links = list("0");
        links.links = [link("a", { is_disabled: false })];
        browser.respond(200, link("a", { is_disabled: true }));
        await links.toggle(links.links[0]);
        assert.deepEqual(browser.requests[0].body, { is_disabled: true });
        assert.equal(toastStore.message, "Disabled");
        browser.respond(200, link("a", { is_disabled: false }));
        await links.toggle(links.links[0]);
        assert.deepEqual(browser.requests[1].body, { is_disabled: false });
        assert.equal(toastStore.message, "Enabled");
    });

    test("a change that fails", async () => {
        const links = list("0");
        links.links = [link("a")];
        browser.respond(403, {
            errors: [{ message: "This link belongs to someone else" }],
        });
        await links.toggle(links.links[0]);
        assert.equal(toastStore.message, "This link belongs to someone else");
        assert.deepEqual(links.links, [link("a")]);
    });

    test("delete", async () => {
        const links = list("0");
        browser.confirm = false;
        await links.remove(link("a"));
        assert.deepEqual(browser.confirmations, [
            "Delete https://s.example/a and its clicks?",
        ]);
        assert.equal(browser.requests.length, 0, "not without a confirmation");

        browser.confirm = true;
        browser.respond(204);
        browser.respond(200, { links: [], total: 0 });
        await links.remove(link("a"));
        assert.equal(browser.requests[0].method, "DELETE");
        assert.equal(browser.requests[0].url, "/api/v1/links/a");
        assert.equal(
            browser.requests[1].method,
            "GET",
            "then the list is loaded again"
        );
        assert.equal(toastStore.message, "Deleted https://s.example/a");
    });

    test("a delete that fails", async () => {
        const links = list("0");
        browser.respond(404, { errors: [{ message: "No such link" }] });
        await links.remove(link("a"));
        assert.equal(toastStore.message, "No such link");
    });

    test("copy", async () => {
        await list("0").copy(link("a"));
        assert.deepEqual(browser.copied, ["https://s.example/a"]);
    });
});

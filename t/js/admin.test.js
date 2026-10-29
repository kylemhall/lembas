"use strict";

const { beforeEach, describe, test } = require("node:test");
const assert = require("node:assert/strict");
const browser = require("./browser.js");

const { adminUsers, toastStore } = browser.Lembas;

beforeEach(() => browser.reset());

const jane = {
    id: 2,
    email: "jane@example.org",
    is_active: true,
    links_count: 4,
};
const john = {
    id: 3,
    email: "john@example.org",
    is_active: true,
    links_count: 0,
};

describe("adminUsers", () => {
    test("every user", async () => {
        const admin = adminUsers();
        browser.respond(200, { users: [jane, john] });
        await admin.init();
        assert.equal(browser.requests[0].url, "/api/v1/admin/users");
        assert.deepEqual(admin.users, [jane, john]);
    });

    test("not for everybody", async () => {
        browser.respond(403, { errors: [{ message: "Admins only" }] });
        await adminUsers().load();
        assert.equal(toastStore.message, "Admins only");
    });

    test("disable and enable", async () => {
        const admin = adminUsers();
        admin.users = [jane, john];
        browser.respond(200, {
            id: 2,
            email: "jane@example.org",
            is_active: false,
        });
        await admin.toggle(jane);
        assert.equal(browser.requests[0].method, "PATCH");
        assert.equal(browser.requests[0].url, "/api/v1/admin/users/2");
        assert.deepEqual(browser.requests[0].body, { is_active: false });
        assert.deepEqual(
            admin.users[0],
            { ...jane, is_active: false },
            "the count of links is kept"
        );
        assert.deepEqual(admin.users[1], john);
        assert.equal(toastStore.message, "Disabled jane@example.org");

        browser.respond(200, {
            id: 2,
            email: "jane@example.org",
            is_active: true,
        });
        await admin.toggle(admin.users[0]);
        assert.deepEqual(browser.requests[1].body, { is_active: true });
        assert.equal(toastStore.message, "Enabled jane@example.org");
    });

    test("a change that is refused", async () => {
        const admin = adminUsers();
        admin.users = [jane];
        browser.respond(400, {
            errors: [{ message: "Admins cannot change their own account" }],
        });
        await admin.toggle(jane);
        assert.equal(
            toastStore.message,
            "Admins cannot change their own account"
        );
        assert.deepEqual(admin.users, [jane]);
    });
});

"use strict";

// A browser for public/js/app.js, in Node: the globals it uses, faked, and what it does with them

const path = require("node:path");

const browser = {
    listeners: {},
    stores: {},
    components: {},
    requests: [],
    responses: [],
    copied: [],
    events: [],
    confirmations: [],
    confirm: true,
    clipboardFails: false,
};

// The next response of fetch: without a body, its JSON cannot be parsed
browser.respond = (status, body) => {
    browser.responses.push({
        status,
        ok: status >= 200 && status < 300,
        statusText: "Status " + status,
        json: async () => {
            if (body === undefined) {
                throw new SyntaxError("Unexpected end of JSON input");
            }
            return body;
        },
    });
};

browser.reset = () => {
    for (const key of [
        "requests",
        "responses",
        "copied",
        "events",
        "confirmations",
    ]) {
        browser[key].length = 0;
    }
    browser.confirm = true;
    browser.clipboardFails = false;
    browser.stores.toast.message = "";
};

globalThis.document = {
    addEventListener: (type, listener) => {
        browser.listeners[type] = listener;
    },
};

globalThis.fetch = async (url, options) => {
    const body =
        options.body === undefined ? undefined : JSON.parse(options.body);
    browser.requests.push({ ...options, url, body });
    return browser.responses.shift();
};

globalThis.Alpine = {
    store(name, value) {
        if (value !== undefined) {
            browser.stores[name] = value;
        }
        return browser.stores[name];
    },
    data(name, factory) {
        browser.components[name] = factory;
    },
};

globalThis.window = {
    Alpine: globalThis.Alpine,
    dispatchEvent: event => browser.events.push(event.type),
    confirm: message => {
        browser.confirmations.push(message);
        return browser.confirm;
    },
};

Object.defineProperty(globalThis, "navigator", {
    configurable: true,
    value: {
        clipboard: {
            writeText: async text => {
                if (browser.clipboardFails) {
                    throw new Error("Not allowed");
                }
                browser.copied.push(text);
            },
        },
    },
});

require(path.join(__dirname, "..", "..", "public", "js", "app.js"));
browser.listeners["alpine:init"]();
browser.Lembas = globalThis.Lembas;

module.exports = browser;

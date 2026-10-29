"use strict";

// The pages of Lembas: Alpine.js components on top of the REST API. No build step: this file is served as it is.
// The CSP build of Alpine.js only evaluates simple expressions, so the logic is here and the templates name it.

// Resolves to the status and the body of the response, or rejects with the message of the error document
async function api(method, path, body) {
    const options = {
        method,
        credentials: "same-origin",
        headers: { Accept: "application/json" },
    };
    if (body !== undefined) {
        options.headers["Content-Type"] = "application/json";
        options.body = JSON.stringify(body);
    }
    const response = await fetch("/api/v1" + path, options);
    const data =
        response.status === 204
            ? null
            : await response.json().catch(() => null);
    if (!response.ok) {
        throw new Error(
            data && data.errors ? data.errors[0].message : response.statusText
        );
    }
    return { status: response.status, data };
}

const toastStore = {
    message: "",
    kind: "success",
    timer: null,
    show(message, kind) {
        this.message = message;
        this.kind = kind;
        clearTimeout(this.timer);
        this.timer = setTimeout(() => this.clear(), 4000);
    },
    clear() {
        this.message = "";
    },
};

function notify(message, kind) {
    Alpine.store("toast").show(message, kind);
}

function copyText(text) {
    return navigator.clipboard.writeText(text).then(
        () => notify("Copied " + text, "success"),
        () => notify("Could not copy, select the link instead", "error")
    );
}

function shortener() {
    return {
        longUrl: "",
        ending: "",
        busy: false,
        result: null,
        note: "",
        error: "",
        async submit() {
            this.busy = true;
            this.error = "";
            const body = { long_url: this.longUrl };
            if (this.ending) {
                body.ending = this.ending;
            }
            try {
                const { status, data } = await api("POST", "/links", body);
                this.result = data;
                this.note =
                    status === 201
                        ? "New link"
                        : "You already had a link for this URL";
                this.longUrl = "";
                this.ending = "";
                window.dispatchEvent(new CustomEvent("lembas:link-created"));
            } catch (error) {
                this.result = null;
                this.error = error.message;
            } finally {
                this.busy = false;
            }
        },
        copy() {
            return copyText(this.result.short_url);
        },
    };
}

// data-all="1" on its element: every link, for the admins
function linkList() {
    return {
        links: [],
        total: 0,
        page: 1,
        perPage: 25,
        q: "",
        all: false,
        loading: true,
        editing: null,
        editUrl: "",
        init() {
            this.all = this.$root.dataset.all === "1";
            return this.load();
        },
        get pages() {
            return Math.max(1, Math.ceil(this.total / this.perPage));
        },
        get empty() {
            return !this.loading && this.links.length === 0;
        },
        async load() {
            this.loading = true;
            const query = new URLSearchParams({
                page: this.page,
                per_page: this.perPage,
            });
            if (this.q) {
                query.set("q", this.q);
            }
            if (this.all) {
                query.set("all", "true");
            }
            try {
                const { data } = await api("GET", "/links?" + query);
                this.links = data.links;
                this.total = data.total;
            } catch (error) {
                notify(error.message, "error");
            } finally {
                this.loading = false;
            }
        },
        search() {
            this.page = 1;
            return this.load();
        },
        next() {
            this.page++;
            return this.load();
        },
        prev() {
            this.page--;
            return this.load();
        },
        copy(link) {
            return copyText(link.short_url);
        },
        startEdit(link) {
            this.editing = link.ending;
            this.editUrl = link.long_url;
        },
        cancelEdit() {
            this.editing = null;
        },
        async saveEdit() {
            await this.change(
                this.editing,
                { long_url: this.editUrl },
                "Saved"
            );
            this.editing = null;
        },
        toggle(link) {
            return this.change(
                link.ending,
                { is_disabled: !link.is_disabled },
                link.is_disabled ? "Enabled" : "Disabled"
            );
        },
        async change(ending, fields, message) {
            try {
                const { data } = await api(
                    "PATCH",
                    "/links/" + encodeURIComponent(ending),
                    fields
                );
                this.links = this.links.map(link =>
                    link.ending === ending ? data : link
                );
                notify(message, "success");
            } catch (error) {
                notify(error.message, "error");
            }
        },
        async remove(link) {
            if (
                !window.confirm("Delete " + link.short_url + " and its clicks?")
            ) {
                return;
            }
            try {
                await api(
                    "DELETE",
                    "/links/" + encodeURIComponent(link.ending)
                );
                notify("Deleted " + link.short_url, "success");
                await this.load();
            } catch (error) {
                notify(error.message, "error");
            }
        },
    };
}

// data-ending on its element: the link and its clicks over the last "days" days, in UTC
function linkStats() {
    return {
        ending: "",
        days: 30,
        link: null,
        stats: null,
        error: "",
        init() {
            this.ending = this.$root.dataset.ending;
            return this.load();
        },
        get perDay() {
            return this.stats ? this.stats.clicks_per_day : [];
        },
        get referers() {
            return this.stats ? this.stats.top_referers : [];
        },
        get total() {
            return this.stats ? this.stats.total : 0;
        },
        get maxClicks() {
            return Math.max(1, ...this.perDay.map(day => day.clicks));
        },
        async load() {
            const path = "/links/" + encodeURIComponent(this.ending);
            const to = new Date();
            const from = new Date(to.getTime() - (this.days - 1) * 86400000);
            const period = new URLSearchParams({
                from: from.toISOString().slice(0, 10),
                to: to.toISOString().slice(0, 10),
            });
            try {
                const [link, stats] = await Promise.all([
                    api("GET", path),
                    api("GET", path + "/stats?" + period),
                ]);
                this.link = link.data;
                this.stats = stats.data;
                this.error = "";
            } catch (error) {
                this.error = error.message;
            }
        },
        setRange(days) {
            this.days = days;
            return this.load();
        },
    };
}

// The key of a new API key is only seen once: in "created", until it is dismissed
function apiKeys() {
    return {
        keys: [],
        label: "",
        created: null,
        busy: false,
        init() {
            return this.load();
        },
        async load() {
            try {
                const { data } = await api("GET", "/api_keys");
                this.keys = data.api_keys;
            } catch (error) {
                notify(error.message, "error");
            }
        },
        async create() {
            this.busy = true;
            try {
                const { data } = await api("POST", "/api_keys", {
                    label: this.label,
                });
                this.created = data;
                this.label = "";
                await this.load();
            } catch (error) {
                notify(error.message, "error");
            } finally {
                this.busy = false;
            }
        },
        copy() {
            return copyText(this.created.key);
        },
        dismiss() {
            this.created = null;
        },
        async revoke(key) {
            const question =
                'Revoke the key "' +
                key.label +
                '"? Scripts that use it will stop working.';
            if (!window.confirm(question)) {
                return;
            }
            try {
                await api("DELETE", "/api_keys/" + key.id);
                notify("Revoked " + key.label, "success");
                await this.load();
            } catch (error) {
                notify(error.message, "error");
            }
        },
    };
}

function register(alpine) {
    alpine.store("toast", toastStore);
    alpine.data("shortener", shortener);
    alpine.data("linkList", linkList);
    alpine.data("linkStats", linkStats);
    alpine.data("apiKeys", apiKeys);
}

globalThis.Lembas = {
    api,
    toastStore,
    notify,
    copyText,
    shortener,
    linkList,
    linkStats,
    apiKeys,
    register,
};
document.addEventListener("alpine:init", () => register(window.Alpine));

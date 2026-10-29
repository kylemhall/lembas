module.exports = {
    arrowParens: "avoid",
    trailingComma: "es5",
    tabWidth: 4,
    useTabs: false,
    overrides: [
        {
            files: ["*.js", "*.ts", "*.vue"],
            excludeFiles: ["public/vendor/**"],
            options: {
                tabWidth: 4,
                useTabs: false,
                trailingComma: "es5",
                arrowParens: "avoid",
            },
        },
    ],
};

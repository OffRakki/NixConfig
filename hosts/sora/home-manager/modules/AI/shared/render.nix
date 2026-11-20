vars: text:
builtins.replaceStrings
(builtins.map (name: "{{${name}}}") (builtins.attrNames vars))
(builtins.attrValues vars)
text

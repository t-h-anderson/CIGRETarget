function cobj = build(mdl)
arguments
    mdl
end

if nargout > 0
    cobj = util.loadSystem(mdl);
else
    util.loadSystem(mdl);
    cobj = [];
end

slbuild(mdl)

end


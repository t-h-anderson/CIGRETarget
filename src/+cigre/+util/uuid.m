function val = uuid()
% Take ownership of the uuid creation so it can be changed in one place if
% the MATLAB internal functionality changes in the future
val = matlab.lang.internal.uuid();
end
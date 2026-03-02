function wordsOut = padToBoundary(wordsIn, padTo)
arguments
    wordsIn (1,:) {mustBeNumeric}
    padTo (1,1) double
end

pad = mod(padTo - mod(numel(wordsIn), padTo), padTo);
wordsOut = [wordsIn, zeros(1, pad)];

end


function wordsOut = padToBoundary(wordsIn, padTo)

pad = mod(padTo - mod(numel(wordsIn), padTo), padTo);
wordsOut = [wordsIn, zeros(1, pad)];

end


classdef DataMap
 
    properties
        Data
        Words (1,:)
        DataType (1,:) string = string.empty
        Sizes (1,:) double = []
        Dims (1,:) cell = {}
    end

    methods
        function obj = DataMap(data, words, dataType, sizes, dims)
            arguments
                data = []
                words (1,:) = []
                dataType (1,:) string = string.empty
                sizes (1,:) double = []
                dims (1,:) cell = {}
            end

            obj.Data = data;
            obj.Words = words;
            obj.DataType = dataType;
            obj.Sizes = sizes;
            obj.Dims = dims;

        end

        function obj = wordsToData(obj, nvp)
            arguments
                obj
                nvp.Packing (1,1) double = 0
            end

            words = obj.Words;
            dataTypes = obj.DataType;
            sizes = obj.Sizes;
            dims = obj.Dims;

            nWords = numel(dataTypes);
            data = cell(1, nWords);
            pos = 1;

            for iWord = 1:nWords

                wordByteSize = sizes(iWord);
                totalBytes = wordByteSize * prod(dims{iWord});

                szMem = max(wordByteSize, nvp.Packing);

                pad = mod(szMem - mod(pos-1, szMem), szMem);

                pos = pos + pad;

                this = words(pos:(pos+totalBytes-1));

                pos = pos + totalBytes;

                dataType = dataTypes(iWord);
                if dataType == "logical"
                    var = (this ~= 0);
                else
                    var = typecast(this, dataType);
                end

                dimensions = dims{iWord};
                dimensions = num2cell(dimensions);

                % Trim word-boundary padding so the variable reshapes
                % back to its original dimensions.
                nVal = prod([dimensions{:}]);
                var = var(1:nVal);

                var = reshape(var, dimensions{:});

                data{iWord} = var;
            end

            obj.Data = data;

        end


    end

    methods (Static)

        function obj = create(data, nvp)
            arguments
                data
                nvp.Target (1,1) string = "uint8"
                nvp.Row (1,1) double = 1
            end

            if isstruct(data)
                data = {data.Variables};
            end

            rowIdx = nvp.Row;
            
            if rowIdx <= size(data, 1) 
                data = data(rowIdx, :);
            else
                data = data([],:);
            end

            target = nvp.Target;

            words = cast([], nvp.Target);
            dataTypes = string.empty();
            sizes = zeros(numel(data), 1);
            dims = cell(size(data, 2),1);
            inputData = cell(size(data, 2),1);

            for i = 1:size(data, 2)

                if iscell(data)
                    input = data{i};
                elseif istimetable(data)
                    input = data{:, i};
                else
                    input = data(:, i);
                end

                if istimetable(input)
                    input = input.Variables;
                    if iscell(input)
                        % Each column in the table must be one data type
                        % for the concat to be type-stable.
                        input = [input{:}];
                    end
                end

                inputData{i} = input;

                val = input;
                dataTypes(i) = class(val);
                if islogical(val)
                    % PSCAD's CIGRE consumer does not accept logical;
                    % coerce to int8 which has the same bit width.
                    val = int8(val);
                end

                dims{i} = size(val);
                val = reshape(val, 1, []);

                try
                    targetVal = typecast(val, target);
                catch
                    % typecast rejects sizes that aren't a whole number
                    % of target words; pad the value out to the next
                    % boundary and retry.
                    n = max(size(typecast(val, "int8")));

                    nTarget = numel(typecast(cast(1, target), "int8"));

                    nPad = (nTarget - n)/n;

                    valHeight = size(val, 1);
                    nPad = nPad./valHeight;

                    c = class(val);
                    pad = zeros(valHeight, nPad, c);

                    paddedVal = [val, pad];

                    targetVal = typecast(paddedVal, target);
                end

                sizes(i) = numel(targetVal)./numel(val);

                if sizes(i) > 1
                    words = util.padToBoundary(words, sizes(i));
                end

                words = [words, targetVal]; %#ok<AGROW>

            end

            obj = cigre.dll.DataMap(inputData, words, dataTypes, sizes, dims);

        end


    end
end


classdef DataMap
 
    properties
        Data
        Words (1,:)
        DataType 
        Sizes
        Dims
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

                % Remove any padding
                nVal = prod([dimensions{:}]);
                var = var(1:nVal);

                var = reshape(var, dimensions{:});
                
                data{iWord} = var;
            end

            obj.Data = data;

        end


    end

    methods (Static)

        % Try using "typecast"
        %in = typecast(firstVal, "uint32");
        %in = [in, secondVal] ; % May do some alignment for doubles, i.e. padding to make sure it fits. This is compiler dependent.
        % Look at xcp toolbox. Has lots of examples

        % Can run an initialise which returns this information
        % address of input.myField - address of input input& - input.myField&
        % capi or code descriptor - getCodeDescriptor, or add to cigre
        % C code to get offsets, matlab code to ask for the data

        % Can we add other functions?
        % All inputs and outputs are in structure, not as separate
        % parameters. Codegen options - interface. Make sure don't use
        % custom storage class. Ignore storage classes, goes back to
        % in/out structs. *codeDescriptorInterface*

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

                % Extract data from cell input
                if iscell(data)
                    input = data{i};
                elseif istimetable(data)
                    input = data{:, i};
                else
                    input = data(:, i);
                end

                % Extract data from timetabels
                if istimetable(input)
                    input = input.Variables;
                    if iscell(input)
                        % Each column in the table must be one data type
                        input = [input{:}];
                    end
                end

                inputData{i} = input;

                % Capture the input data type so we can cast it back later
                val = input;
                dataTypes(i) = class(val);
                if islogical(val)
                    % Logical are not supported in PSCAD
                    val = int8(val);
                end

                % Save the dimensions before reshaping to a vector
                dims{i} = size(val);
                val = reshape(val, 1, []);

                % Convert to target datatype
                try
                    targetVal = typecast(val, target);
                catch
                   
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

                % Save the number of target data types per val
                sizes(i) = numel(targetVal)./numel(val);

                % Pad to word boundaries
                if sizes(i) > 1
                    padTo = sizes(i);
                    words = util.padToBoundary(words, padTo);
                end

                % Store the resulting words
                words = [words, targetVal]; %#ok<AGROW>

            end

            obj = cigre.dll.DataMap(inputData, words, dataTypes, sizes, dims);

        end


    end
end


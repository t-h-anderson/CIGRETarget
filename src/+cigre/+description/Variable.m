classdef Variable
    %VARIABLE Summary of this class goes here
    %   Detailed explanation goes here
    
    properties
        Name (1,1) string = ""
        Type (1,1) string = ""
        Pointers (1,1) string = ""
    end
    
    methods
        function obj = Variable(nvp)
            arguments
                nvp.?cigre.description.Variable
            end

            fs = string(fields(nvp));
            for i = 1:numel(fs)
                f = fs(i);
                obj.(f) = nvp.(f);
            end
            
        end
        
    end

    methods (Static)

        function objs = create(nvp)
            arguments
                nvp.Name string
                nvp.Type string
                nvp.Pointers string
            end

            objs = cigre.description.Variable.empty(1,0);

            fs = string(fields(nvp));
            fn = numel(fs);

            n = zeros(fn, 1);
            for i = 1:fn
                f = fs(i);
                n(i) = numel(nvp.(f));
            end

            maxN = max(n);

            isOk = all((n == 1) | (n == maxN));
            if ~isOk
                error("Entry must be scalar or all the same lenght");
            end

            for i = 1:maxN
                in = nvp;

                for j = 1:fn
                    f = fs(j);

                    val = nvp.(f);
                    if numel(val) ~= 1
                        val = val(i);
                    end
                    in.(f) = val;
                end

                incell = namedargs2cell(in);

                objs(i) = cigre.description.Variable(incell{:});

            end

        end

    end

end


classdef Variable
    %VARIABLE Summary of this class goes here
    %   Detailed explanation goes here
    
    properties
        GraphicalName (:,1) string = ""
        Name (:,1) string = ""
        Type (:,1) string = ""
        Pointers (:,1) string = ""
        BaseType (:,1) string = ""
        Dimensions = [NaN, NaN]
        Min (:,1) = NaN
        Max (:,1) = NaN
        DefaultValue (:,1) = NaN
    end
    
    methods
        function obj = Variable(nvp)
            arguments
                nvp.?cigre.description.Variable
            end

            fs = string(fields(nvp));
            for i = 1:numel(fs)
                f = fs(i);
                val = nvp.(f);
                if ~isempty(val)
                    obj.(f) = val;
                end
            end
            
        end
        
    end

    methods (Static)

        function objs = create(nvp)
            arguments
                nvp.?cigre.description.Variable
                nvp.Dimensions
            end

            objs = cigre.description.Variable.empty(1,0);

            fs = string(fields(nvp));
            fn = numel(fs);

            n = zeros(fn, 1);
            for i = 1:fn
                f = fs(i);
                % Everything is a vector, Dimension is cell array
                % containing potentially disperate vectors
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
                    if numel(val) > 1
                        % Everything scalar apart from Dimension which is a
                        % cell array of potentially disperate vectors
                        val = val(i);
                    end

                    if ~isempty(val)
                        if f == "Dimensions"
                            in.(f) = val{:};
                        else
                            in.(f) = val;
                        end
                    end
                end

                incell = namedargs2cell(in);

                objs(i) = cigre.description.Variable(incell{:});

            end

        end

    end

end


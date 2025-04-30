classdef TypeTestEnum < Simulink.IntEnumType
    
    enumeration
        Red(0)
        Blue(1)
    end %enumeration
    
    methods (Static)
        function retVal = getHeaderFile()
            retVal = 'myEnumHdr.h';
        end %function
        
        function retVal = getDataScope()
            retVal = 'Exported';
        end %function
    end %methods
    
end %classdef
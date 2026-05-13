function sl_customization(cm)
% Copyright 2024 The MathWorks, Inc.
%
% To pick up new checks: Advisor.Manager.refresh_customizations().
% To refresh all checks: Advisor.Manager.update_customizations().

cm.addModelAdvisorCheckFcn(@defineModelAdvisorChecks);

end

function defineModelAdvisorChecks
cigre.advisor.detailStyleChecks.Cigre0001ConfigSet;
cigre.advisor.detailStyleChecks.Cigre0002VirtualBus;
cigre.advisor.detailStyleChecks.Cigre0003InterfaceTypes;
cigre.advisor.detailStyleChecks.Cigre0004TrigerSubsystem;
end
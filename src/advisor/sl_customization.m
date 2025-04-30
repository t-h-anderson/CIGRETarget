function sl_customization(cm)

% Copyright 2024 The MathWorks, Inc.
 % Adds new:      Advisor.Manager.refresh_customizations()
 % Refreshed all: Advisor.Manager.update_customizations()

% register custom checks 
cm.addModelAdvisorCheckFcn(@defineModelAdvisorChecks);

end

% -----------------------------
% defines Model Advisor Checks
% -----------------------------
function defineModelAdvisorChecks

% Register custom checks
cigre.advisor.detailStyleChecks.Cigre0001ConfigSet;
cigre.advisor.detailStyleChecks.Cigre0002VirtualBus;
cigre.advisor.detailStyleChecks.Cigre0003InterfaceTypes;
cigre.advisor.detailStyleChecks.Cigre0004TrigerSubsystem;
end
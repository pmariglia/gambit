%module contingency
%include typemaps.i

%{
#include "../game/game.h"
%}

%nodefault;
class gbtNfgContingency {
public:
  virtual ~gbtNfgContingency();
};

%extend gbtNfgContingency {
  gbtGameStrategy GetStrategy(const gbtGamePlayer &p) const
    { return (*self)->GetStrategy(p); }
  void SetStrategy(const gbtGameStrategy &s)
    { (*self)->SetStrategy(s); }

  gbtGameOutcome GetOutcome(void) const
    { return (*self)->GetOutcome(); }
  void SetOutcome(const gbtGameOutcome &c) 
    { (*self)->SetOutcome(c); }

  gbtRational GetPayoff(const gbtGamePlayer &p) const
    { return (*self)->GetPayoff(p); }
};


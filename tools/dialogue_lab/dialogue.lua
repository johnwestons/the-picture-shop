local D={}
D.lines={
    {'greeting','Hello! Good to see you.','Say hello'},
    {'neutral','I am getting the next order ready.','Ask about work'},
    {'happy','We finished the order early!','Share good news'},
    {'curious','Which paper should we use for this one?','Ask a question'},
    {'agreement','Sounds good. I can do that.','Offer a plan'},
    {'disagreement','Hmm. I do not think that will fit.','Suggest the wrong size'},
    {'surprised','Whoa! That is a huge order!','Reveal a big order'},
    {'annoyed','The cutter is jammed again.','Ask about a jam'},
    {'thanks','Thanks for helping me out!','Offer help'},
    {'worried','Are we going to make the deadline?','Discuss the deadline'},
    {'sad','Oh. I was hoping that would work.','Deliver bad news'},
    {'goodbye','See you tomorrow!','Say goodbye'},
}
function D.new(clips)
    return setmetatable({clips=clips,gain=.35,delay=0,cps=0,hold=2.5,clock=0,plays=0,events={}}, {__index=D})
end
function D:stop()
    if self.source then self.source:stop() end
    self.source=nil;self.active=nil;self.pending=false
end
function D:trigger(line)
    self:stop();self.active=line;self.clock=0;self.pending=true
    self.source=self.clips[line[1]]
    self.missingClip=not self.source
    self.pending=self.source~=nil
    local duration=self.source and self.source:getDuration() or 0
    self.expires=math.max(self.hold,self.source and self.delay+duration+.3 or 0,self.cps>0 and #line[2]/self.cps+.8 or 0)
    self.events={bubble=0};self:update(0)
end
function D:update(dt)
    if not self.active then return end
    self.clock=self.clock+dt
    if self.pending and self.source and self.clock>=self.delay then
        self.source:setVolume(self.gain);self.source:play();self.pending=false
        self.plays=self.plays+1;self.events.audio=self.clock
    end
    if self.clock>=self.expires then self:stop() end
end
function D:text()
    if not self.active then return '' end
    return self.cps==0 and self.active[2] or self.active[2]:sub(1,math.floor(self.clock*self.cps))
end
return D

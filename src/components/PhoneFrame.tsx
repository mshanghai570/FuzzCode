import React, { useState, useEffect } from 'react';
import { Home, MessageSquare, Terminal, Sliders, Settings, Wifi } from 'lucide-react';
import { fuzzAudio } from '../services/audioService';

interface PhoneFrameProps {
  activeTab: string;
  setActiveTab: (tab: string) => void;
  children: React.ReactNode;
}

export const PhoneFrame: React.FC<PhoneFrameProps> = ({
  activeTab,
  setActiveTab,
  children
}) => {
  const [currentTime, setCurrentTime] = useState('9:41');

  useEffect(() => {
    const update = () => {
      const now = new Date();
      setCurrentTime(now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', hour12: false }));
    };
    update();
    const interval = setInterval(update, 30000);
    return () => clearInterval(interval);
  }, []);

  const navItems = [
    { id: 'home', label: 'Home', icon: Home },
    { id: 'chat', label: 'Chat', icon: MessageSquare },
    { id: 'agents', label: 'Agents', icon: Terminal },
    { id: 'providers', label: 'Endpoints', icon: Sliders },
    { id: 'settings', label: 'Settings', icon: Settings },
  ];

  return (
    <div className="relative mx-auto my-4 w-[390px] h-[844px] rounded-[52px] bg-[#1a1c23] p-[10px] shadow-2xl shadow-black/80 ring-1 ring-white/10 select-none">
      {/* Outer Titanium Bezel */}
      <div className="relative w-full h-full rounded-[44px] bg-[#090a0d] overflow-hidden flex flex-col border border-[#2b303f]">
        
        {/* iOS Status Bar */}
        <div className="relative z-30 flex items-center justify-between px-7 pt-3.5 pb-1 text-xs font-semibold text-white tracking-tight">
          <span className="tabular-nums font-mono">{currentTime}</span>
          
          {/* Dynamic Island */}
          <div className="absolute left-1/2 -translate-x-1/2 top-2.5 w-[110px] h-[30px] bg-black rounded-full flex items-center justify-between px-3 shadow-inner">
            <div className="w-2.5 h-2.5 rounded-full bg-[#15171e]" />
            <div className="w-2.5 h-2.5 rounded-full bg-emerald-500/80 shadow-[0_0_8px_#10b981]" />
          </div>

          <div className="flex items-center gap-1.5 text-slate-300">
            <Wifi className="w-3.5 h-3.5" />
            <span className="text-[10px] font-mono">5G</span>
            {/* Battery icon */}
            <div className="w-5 h-2.5 border border-slate-300 rounded-[3px] p-[1px] flex items-center">
              <div className="w-full h-full bg-emerald-400 rounded-[1.5px]" />
            </div>
          </div>
        </div>

        {/* Screen Content Canvas */}
        <div className="flex-1 overflow-y-auto overflow-x-hidden relative flex flex-col text-slate-100">
          {children}
        </div>

        {/* Native iOS Tab Bar (Fixed Bottom Thumb Zone) */}
        <div className="relative z-30 border-t border-[#1a1d26] bg-[#0c0d12]/95 backdrop-blur-md px-2 pt-1 pb-4">
          <div className="grid grid-cols-5 items-center">
            {navItems.map((item) => {
              const Icon = item.icon;
              const isActive = activeTab === item.id;
              return (
                <button
                  key={item.id}
                  onClick={() => {
                    fuzzAudio.playStomp();
                    setActiveTab(item.id);
                  }}
                  className="flex flex-col items-center justify-center py-1 min-h-[44px] cursor-pointer group"
                >
                  <Icon
                    className={`w-5 h-5 transition-transform group-active:scale-90 ${
                      isActive ? 'text-emerald-400 stroke-[2.4]' : 'text-slate-500 hover:text-slate-300'
                    }`}
                  />
                  <span
                    className={`text-[10px] font-medium tracking-tight mt-1 ${
                      isActive ? 'text-emerald-400 font-semibold' : 'text-slate-500'
                    }`}
                  >
                    {item.label}
                  </span>
                </button>
              );
            })}
          </div>

          {/* iOS Home Indicator Bar */}
          <div className="w-32 h-1 bg-white/30 rounded-full mx-auto mt-1" />
        </div>
      </div>
    </div>
  );
};

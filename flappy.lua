local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local Player     = Players.LocalPlayer
local PlayerGui  = Player:WaitForChild("PlayerGui")
local Enabled    = true

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name           = "AutoFlappyUI"
ScreenGui.ResetOnSpawn   = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent         = PlayerGui

local Main = Instance.new("Frame")
Main.Size             = UDim2.new(0, 160, 0, 58)
Main.Position         = UDim2.new(0, 20, 0.5, -29)
Main.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
Main.BorderSizePixel  = 0
Main.Active           = true
Main.Draggable        = true
Main.Parent           = ScreenGui
Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 10)

local TitleBar = Instance.new("TextLabel")
TitleBar.Size                   = UDim2.new(1, 0, 0, 18)
TitleBar.Position               = UDim2.new(0, 0, 0, 2)
TitleBar.BackgroundTransparency = 1
TitleBar.Text                   = "AutoFlappy v5"
TitleBar.TextColor3             = Color3.fromRGB(120, 120, 120)
TitleBar.TextSize               = 11
TitleBar.Font                   = Enum.Font.GothamBold
TitleBar.TextXAlignment         = Enum.TextXAlignment.Center
TitleBar.Parent                 = Main

local Toggle = Instance.new("TextButton")
Toggle.Size             = UDim2.new(1, -10, 0, 30)
Toggle.Position         = UDim2.new(0, 5, 0, 22)
Toggle.BackgroundColor3 = Color3.fromRGB(50, 160, 230)
Toggle.BorderSizePixel  = 0
Toggle.Text             = "Auto: ON"
Toggle.TextColor3       = Color3.fromRGB(255, 255, 255)
Toggle.TextSize         = 13
Toggle.Font             = Enum.Font.GothamBold
Toggle.AutoButtonColor  = false
Toggle.Parent           = Main
Instance.new("UICorner", Toggle).CornerRadius = UDim.new(0, 8)

local function updateUI()
	Toggle.Text             = Enabled and "Auto: ON" or "Auto: OFF"
	Toggle.BackgroundColor3 = Enabled and Color3.fromRGB(50,160,230) or Color3.fromRGB(170,55,55)
end
Toggle.MouseButton1Click:Connect(function() Enabled = not Enabled; updateUI() end)

task.spawn(function()
	local BaseFlappy
	while true do
		local ok = pcall(function() BaseFlappy = PlayerGui.Game.Sections.ParkPhoneUI.BaseFlappy end)
		if ok and BaseFlappy then break end
		task.wait(0.5)
	end

	local GameArea   = BaseFlappy:WaitForChild("GameArea", 30)
	local TapOverlay = GameArea:WaitForChild("TapOverlay", 30)

	local GRAVITY     = 680
	local TAP_IMPULSE = -165
	local SIM_DT      = 1/60
	local SIM_STEPS   = 72
	local PIPE_PAT    = "^Pipe_%d+_([TB])$"
	local COL_X_TOL   = 3

	-- Medido diretamente do dump:
	-- pipe_T_bottom=203.706, safeA_effTop=207.969  → diferença=4.263px
	-- pipe_B_top=255.620,    safeA_effBot=251.356  → diferença=4.264px
	-- O cap ENTRA dentro do vão: effTop = T.bottom + CAP_PX, effBottom = B.top - CAP_PX
	local CAP_PX = 5.0  -- 4.26 medido + ~0.74 de margem de segurança extra

	local function tap()
		if typeof(firesignal) == "function" then
			pcall(firesignal, TapOverlay.MouseButton1Down)
			pcall(firesignal, TapOverlay.MouseButton1Click)
		end
		if typeof(firebutton) == "function" then pcall(firebutton, TapOverlay, "") end
		pcall(function() TapOverlay:Activate() end)
	end

	local function getRect(obj)
		local p, s = obj.AbsolutePosition, obj.AbsoluteSize
		return {
			left=p.X, right=p.X+s.X, top=p.Y, bottom=p.Y+s.Y,
			cx=p.X+s.X*.5, cy=p.Y+s.Y*.5, width=s.X, height=s.Y,
		}
	end

	local bird = nil
	local function findBird()
		for _, obj in ipairs(GameArea:GetChildren()) do
			if obj:IsA("GuiObject") and obj.Name:lower()=="bird" then bird=obj; return end
		end
	end
	findBird()
	GameArea.ChildAdded:Connect(function(obj)
		if obj:IsA("GuiObject") and obj.Name:lower()=="bird" then bird=obj end
	end)
	GameArea.ChildRemoved:Connect(function(obj)
		if obj==bird then bird=nil end
	end)

	local pipeSpeed=50
	local prevPipePos={}

	local function measurePipeSpeed(dt)
		local newPos,deltas={},{}
		for _, obj in ipairs(GameArea:GetChildren()) do
			if obj:IsA("GuiObject") and obj.Name:match(PIPE_PAT) then
				local cx=obj.AbsolutePosition.X
				local prev=prevPipePos[obj]
				if prev and dt>0.002 then
					local spd=(prev-cx)/dt
					if spd>5 and spd<600 then table.insert(deltas,spd) end
				end
				newPos[obj]=cx
			end
		end
		prevPipePos=newPos
		if #deltas>0 then
			local sum=0; for _,v in ipairs(deltas) do sum+=v end
			pipeSpeed=pipeSpeed*0.8+(sum/#deltas)*0.2
		end
	end

	local function getColumns(birdRight)
		local pipes={}
		for _, obj in ipairs(GameArea:GetChildren()) do
			if obj:IsA("GuiObject") and obj.Visible then
				local side=obj.Name:match(PIPE_PAT)
				if side then
					local p,s=obj.AbsolutePosition,obj.AbsoluteSize
					local r={left=p.X,right=p.X+s.X,top=p.Y,bottom=p.Y+s.Y,cx=p.X+s.X*.5}
					if r.right>birdRight-4 then table.insert(pipes,{r=r,side=side}) end
				end
			end
		end
		local cols={}
		for _, p in ipairs(pipes) do
			local found=nil
			for _, col in ipairs(cols) do
				if math.abs(p.r.cx-col.cx)<=COL_X_TOL then found=col; break end
			end
			if not found then
				found={cx=p.r.cx,left=p.r.left,right=p.r.right,T=nil,B=nil}
				table.insert(cols,found)
			end
			found.left =math.min(found.left, p.r.left)
			found.right=math.max(found.right,p.r.right)
			found.cx   =(found.left+found.right)*.5
			if p.side=="T" then
				if not found.T or p.r.bottom>found.T.bottom then found.T=p.r end
			else
				if not found.B or p.r.top<found.B.top then found.B=p.r end
			end
		end
		local valid={}
		for _, col in ipairs(cols) do
			if col.T and col.B and col.B.top>col.T.bottom then table.insert(valid,col) end
		end
		table.sort(valid,function(a,b) return a.left<b.left end)
		return valid
	end

	local function buildCorridor(col, bRect)
		-- cap ENTRA no vão: effTop sobe, effBottom desce
		local effTop    = col.T.bottom + CAP_PX
		local effBottom = col.B.top    - CAP_PX
		local effH      = effBottom - effTop

		local minNeeded = bRect.height + 8
		if effH < minNeeded then return nil end

		local halfB  = bRect.height * 0.5
		local margin = halfB + 3.0
		if margin*2 >= effH then margin=(effH-bRect.height)*.5-0.5 end

		local safeTop    = effTop    + margin
		local safeBottom = effBottom - margin
		local distLeft   = col.left  - bRect.right

		return {
			left=col.left, right=col.right,
			hitLeft=col.left, hitRight=col.right,
			distLeft=distLeft,
			bodyTop=col.T.bottom, bodyBottom=col.B.top,
			effTop=effTop, effBottom=effBottom, effH=effH,
			safeTop=safeTop, safeBottom=safeBottom,
			center=(safeTop+safeBottom)*.5,
			minCY=effTop    + halfB + 1.0,
			maxCY=effBottom - halfB - 1.0,
		}
	end

	local function computeTarget(corridors)
		local c1=corridors[1]
		if not c1 then return nil end
		local c2=corridors[2]
		local base=c1.center

		if c2 then
			local d=c2.center-c1.center
			local bias=0.5
			if d>30 then bias=0.70 elseif d>15 then bias=0.62
			elseif d<-30 then bias=0.30 elseif d<-15 then bias=0.38 end

			local exitY=c1.safeTop+(c1.safeBottom-c1.safeTop)*bias
			local dl=c1.distLeft
			local prep=0.0
			if dl<-8 then prep=1.0 elseif dl<8 then prep=0.90
			elseif dl<22 then prep=0.76 elseif dl<42 then prep=0.56
			elseif dl<68 then prep=0.34 elseif dl<100 then prep=0.16 end

			base=c1.center+(exitY-c1.center)*prep
		end

		return math.clamp(base, c1.minCY, c1.maxCY)
	end

	local function simulate(bRect, velY, corridors, doTap, aT, aB)
		local y=bRect.cy
		local v=doTap and TAP_IMPULSE or velY
		local risk=0.0
		local hw=bRect.height*.5

		for i=1,SIM_STEPS do
			v=v+GRAVITY*SIM_DT
			y=y+v*SIM_DT

			local bTop=y-hw
			local bBot=y+hw

			if bTop<aT+2 then risk+=10000+(aT+2-bTop)*800 end
			if bBot>aB-2 then risk+=10000+(bBot-(aB-2))*800 end

			for idx=1, math.min(#corridors,3) do
				local c=corridors[idx]
				local w=idx==1 and 1.0 or (idx==2 and 0.55 or 0.25)
				local t=i*SIM_DT
				local pL=c.hitLeft  - pipeSpeed*t
				local pR=c.hitRight - pipeSpeed*t

				if bRect.right>pL and bRect.left<pR then
					if bTop<c.effTop then
						risk+=(12000+(c.effTop-bTop)*800)*w
					elseif bBot>c.effBottom then
						risk+=(12000+(bBot-c.effBottom)*800)*w
					else
						local minGap=math.min(y-c.effTop-hw, c.effBottom-y-hw)
						if minGap<6 then risk+=(6-minGap)*300*w end
					end
				end
			end

			if v<-160 and bTop<aT+30 then risk+=1500 end
			if v>250  and bBot>aB-40  then risk+=1500 end
		end

		return risk
	end

	local lastTap=0
	local lastY=nil
	local lastTime=tick()
	local velY=0
	local smoothVelY=0
	local noTapUntil=0
	local lastTarget=nil
	local MIN_INTERVAL=0.076
	local EMRG_INTERVAL=0.038

	RunService.Heartbeat:Connect(function()
		if not Enabled then return end
		if not bird or not bird.Parent then findBird(); return end

		local now=tick()
		local b=getRect(bird)
		local ap=GameArea.AbsolutePosition
		local as=GameArea.AbsoluteSize
		local aT=ap.Y
		local aB=aT+as.Y
		local dt=math.max(now-lastTime,1/240)

		measurePipeSpeed(dt)

		if lastY then
			velY=(b.cy-lastY)/dt
			smoothVelY=smoothVelY*0.40+velY*0.60
		end
		lastY=b.cy
		lastTime=now

		local cols=getColumns(b.right)
		local corridors={}
		for _, col in ipairs(cols) do
			local c=buildCorridor(col,b)
			if c then table.insert(corridors,c) end
		end

		if #corridors==0 then
			local midY=(aT+aB)*.5
			table.insert(corridors,{
				left=math.huge,right=math.huge,hitLeft=math.huge,hitRight=math.huge,
				distLeft=math.huge,bodyTop=aT+8,bodyBottom=aB-20,
				effTop=aT+8,effBottom=aB-20,effH=aB-aT-28,
				safeTop=aT+20,safeBottom=aB-32,center=midY,
				minCY=aT+b.height*.5+8,maxCY=aB-b.height*.5-20,
			})
		end

		local c1=corridors[1]
		local target=computeTarget(corridors)
		if not target then return end

		if lastTarget then
			target=math.clamp(target,lastTarget-12,lastTarget+12)
			target=lastTarget*0.22+target*0.78
		end
		lastTarget=target

		local predT=math.clamp(0.06+math.abs(smoothVelY)/3000,0.045,0.110)
		local predCY=b.cy+smoothVelY*predT+0.5*GRAVITY*predT*predT
		local predTop=predCY-b.height*.5
		local predBot=predCY+b.height*.5

		local riskNo =simulate(b,smoothVelY,corridors,false,aT,aB)
		local riskTap=simulate(b,smoothVelY,corridors,true, aT,aB)

		local err    =b.cy  -target
		local predErr=predCY-target

		local dz=5.5
		if     c1.distLeft<8  then dz=1.0
		elseif c1.distLeft<20 then dz=2.0
		elseif c1.distLeft<42 then dz=3.2
		end

		local shouldTap=false
		local emergency=false

		if riskTap<riskNo-80 then shouldTap=true end
		if err>dz and predErr>dz and smoothVelY>-70 then shouldTap=true end
		if smoothVelY>130 and predErr>-4 then shouldTap=true end

		if b.bottom>=c1.effBottom-3 or predBot>=c1.effBottom-5 then
			shouldTap=true; emergency=true
		end

		if b.top<=c1.effTop+3 or predTop<=c1.effTop+5 then
			shouldTap=false; emergency=false
			noTapUntil=math.max(noTapUntil,now+0.115)
		end

		if smoothVelY<-145 and b.cy<target+6 then
			shouldTap=false; emergency=false
			noTapUntil=math.max(noTapUntil,now+0.080)
		end

		if predTop<=aT+5 then
			shouldTap=false; emergency=false
			noTapUntil=math.max(noTapUntil,now+0.130)
		end

		local c2=corridors[2]
		if c2 and not emergency then
			if c2.center>c1.center+14 and err<2 and smoothVelY<10 then
				shouldTap=false
				noTapUntil=math.max(noTapUntil,now+0.055)
			end
		end

		if c1.distLeft<b.width*2.5 then
			if b.top<=c1.effTop+4 or predTop<=c1.effTop+6 then
				shouldTap=false; emergency=false
				noTapUntil=math.max(noTapUntil,now+0.115)
			end
			if b.bottom>=c1.effBottom-4 or predBot>=c1.effBottom-6 then
				shouldTap=true; emergency=true
			end
		end

		if now<noTapUntil and not emergency then shouldTap=false end

		if shouldTap and (now-lastTap)>=(emergency and EMRG_INTERVAL or MIN_INTERVAL) then
			tap()
			lastTap=now
			smoothVelY=TAP_IMPULSE
		end
	end)

	print("[AutoFlappy v5] OK")
end)

updateUI()

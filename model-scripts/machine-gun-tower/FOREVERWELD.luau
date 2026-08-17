-- FOREVERWELD > Seat
	
local weld = Instance.new("Weld") 
weld.Part0 = script.Parent
weld.Part1 = script.Parent.Parent["base"] 
weld.C0 = script.Parent.CFrame:inverse() 
weld.C1 = script.Parent.Parent["base"] .CFrame:inverse() 
weld.Parent = script.Parent
		
		


local a = script.Parent.Weld:clone()
local co=script.Parent.Weld.C0
local c1 = script.Parent.Weld.C1
local p1 = script.Parent.Weld.Part1
function poo(part)
	if part.Name =="Weld" then
		local b =a:clone()
		b.Parent=script.Parent
		b.C0 = co
		b.C1 =c1
		b.Part1 = p1
	end
end
script.Parent.ChildRemoved:connect(poo)
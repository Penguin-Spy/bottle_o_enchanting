spawn(fn -> MC.Server.listen(25565) end)
IO.gets("press enter to quit\n")
System.halt()

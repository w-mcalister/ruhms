#library(geometry)
library(sp)
source('./section_charts.R')


###    Really Useful Hydraulic Modelling Scripts (RUHMS) is a program for basic
###    hydraulic modelling of bed-control interventions in waterways.
###    Copyright (C) 2020 William McAlister


### Improvements To Do:
###
### Generally needs a bit of reform to the structure. Smaller functions etc.
### Shoelace algorithm to calculate xsec.area so the sp becomes redundant
### Interpolation
### Have a boolean variable in the input to exclude a site from the analysis
### Separate pre- and post-intervention transects into separate lists
### creek model should take a list of matrices
### add in the capacity for existing structures
### Style the x-section charts to look nicer
### Correct the scaling of charts
### MCCC.barplot to ignore negative values

MCCC.blue <- '#5876b0'
MCCC.brown <- '#6b2223'
MCCC.green <- '#395624'
MCCC.teal <- '#1f6e6e'
MCCC.purple <- '#6647a0'
MCCC.grey <- '#4e4e4e'

read.global.mapper.csv <- function(fname){
  raw.transect <- read.csv(fname)
  transect.data <- raw.transect[ ,c(6,4)]
  colnames(transect.data) <- c('distance', 'elevation')
  return(as.matrix(transect.data))
}

read.qgis.csv <- function(fname){
  raw.transect <- read.csv(fname)
  transect.data <- raw.transect[ , c(1,2)]
  colnames(transect.data) <- c('distance', 'elevation')
  return(as.matrix(transect.data))
}

read.coord.csv <- function(fname){
  raw.transect <- read.csv(fname)
  transect.data <- raw.transect[ , c(1,4)]
  colnames(transect.data) <- c('distance', 'elevation')
  return(as.matrix(transect.data))
}

### this version of transect.area uses the geometry plugin instea of sp
## transect.area <- function(coords){
##   # Takes a numerical data frame specifying coordinates for
##   # the vertices of a polygon and returns the area.
##   return(polyarea(coords[ ,'distance'], coords[ , 'elevation']))
## }

transect.area <- function(df){
  # Takes a numerical data frame specifying coordinates for
  # the vertices of a polygon and returns the area.
    perimeter.poly <- Polygon(as.matrix((df)))
    perimeter.poly <- SpatialPolygons(list(Polygons(list(perimeter.poly), 'x')))
    #plot(perimeter.poly)
    #Sys.sleep(2)
  return(perimeter.poly@polygons[[1]]@Polygons[[1]]@area )
}

get.thalweg <- function(coords){
       #takes coorinates and returns the thalweg
    return(min(coords[ , 2]))}


transect.model <- function(transect.coords, topbank.elevation,
                           spill.elevation=NA, thalweg.elevation=NA,
                           distance.to.bottom=NA, site.code=''){
    ### transect.coords should be a two column matrix of x and y coordinates
    ###
    ### Note that the convention is to draw a stream cross-section looking
    ### upstream so that the true left bank of the stream is on the right side
    ### of the page. Wherever this code refers to left or right banks IT IS
    ### REFERRING TO PAGE SIDE not the true left or right bank.
    ### I wrote the original version before I was familiar with the convention.
    thalweg.index <- which.min(transect.coords[ , 2])
    tmp.thalweg.elevation <- min(transect.coords[ , 2])
    msg <- paste(
        'thalweg: ', transect.coords[thalweg.index, 2], '\n',
        'left bank: ', max(transect.coords[1:thalweg.index, 2]), '\n',
        'right bank: ',
        max(transect.coords[thalweg.index:nrow(transect.coords), 2]), '\n',
        'topbank: ', topbank.elevation
        )
    if(!any(transect.coords[1:thalweg.index , 2] >= topbank.elevation)){
        message('Specified topbank elevation is higher than the right bank.')
        message(msg)
    }
    ### Assert that the parameters given make sense
    if(!any(transect.coords[thalweg.index:nrow(transect.coords), 2] >=
            topbank.elevation)){
        message('specified topbank elevation is higher than the left bank')
        message(msg)
    }
    if(!is.na(thalweg.elevation)){
        message(paste(
            'site', site.code, 'thalweg specified at:', thalweg.elevation,
            '\nelevation is', tmp.thalweg.elevation, 'in the coordinates\n',
            '... overwriting'
        ))
    }
    thalweg.elevation <- tmp.thalweg.elevation
    ### choose which points are at the extreme left and right banks:
    l.bank.index <- which(transect.coords[1:thalweg.index , 2]
                          >= topbank.elevation)
    l.bank.index <- l.bank.index[length(l.bank.index)]
    r.bank.index <- which(
        transect.coords[(thalweg.index+1):nrow(transect.coords), 2] >=
        topbank.elevation) + thalweg.index
    r.bank.index <- r.bank.index[1]
    ### set the topbank heights to be equal so that the water level is a flat
    ### line
    transect.coords[l.bank.index, 2] <- topbank.elevation
    transect.coords[r.bank.index, 2] <- topbank.elevation
    ### got all the pre-intervention hydroloical data:
    pre.intervention.data <- c(
        'depth' = topbank.elevation-thalweg.elevation,
        'xsec.area' = transect.area(
            transect.coords[l.bank.index:r.bank.index, ]),
        'base.channel.width' = transect.coords[r.bank.index, 1] -
            transect.coords[l.bank.index, 1],
        'wp.length' = LineLength(transect.coords[l.bank.index:r.bank.index, ])
    )
    if(is.na(spill.elevation)){
        ### if no structure height was specified the intervention data is
        ### returned with NAs
        print(spill.elevation)
        wp.coords <- transect.coords[l.bank.index:r.bank.index, ]
        structure.coords <- NA
        post.intervention.data <- NA
        l.spill.index <- NA
        r.spill.index <- NA
    } else {
        ### else if a structure height has been specified {
        ### first decide which point is at the spill height of the proposed
        ### structure
        l.spill.index <- which(transect.coords[1:thalweg.index , 2]
                          >= spill.elevation)
        l.spill.index <- l.spill.index[length(l.spill.index)]
        r.spill.index <- which(
            transect.coords[(thalweg.index+1):nrow(transect.coords), 2] >=
            spill.elevation) + thalweg.index
        r.spill.index <- r.spill.index[1]
        ### Quick debug print
        #print(c(l.bank.index, l.spill.index))
        #print(c(r.bank.index, r.spill.index))
        ### Set each spill coordinate to the spill height so that the top
        ### of the structure is a flat line
        ### this will need to be a more complex interpolation method later
        transect.coords[l.spill.index, 2] <- spill.elevation
        transect.coords[r.spill.index, 2] <- spill.elevation
        ### a set of coordinates of the wetted perimeter and the structure
        ### coords
        wp.coords <- rbind(transect.coords[l.bank.index:l.spill.index, ],
                           transect.coords[r.spill.index:r.bank.index, ])
        structure.coords <- transect.coords[
            l.spill.index:r.spill.index, ]
    ### package the parameters
        post.intervention.data <- c(
            'pi.depth' = topbank.elevation-spill.elevation,
            'pi.xsec.area' = transect.area(wp.coords),
            'structure.xsec.area' = transect.area(structure.coords),
            'structure.width' = transect.coords[r.spill.index, 1] -
                transect.coords[l.spill.index, 1],
            'pi.wp.length' = LineLength(wp.coords)
        )
    }
    ## ## Debug plot the significant points
     ## plot(transect.coords, main=site.code)
     ## points(transect.coords[thalweg.index, ], col='green')
     ## points(transect.coords[c(l.bank.index, r.bank.index), ], col='red')
     ## points(transect.coords[c(l.spill.index, r.spill.index), ], col='blue')
    ###
    return(list(
        'site.code' = site.code,
        'data' = c(pre.intervention.data, post.intervention.data),
        'transect.coords' = transect.coords,
        'wp.coords' = wp.coords,
        'structure.coords' = structure.coords,
        'geometry' = c(
            'thalweg.index' = thalweg.index,
            'l.bank.index' = l.bank.index,
            'r.bank.index' = r.bank.index,
            'l.spill.index' = l.spill.index,
            'r.spill.index' = r.spill.index
        ),
        'parameters' = c(
            'thalweg.elevation' = thalweg.elevation,
            'topbank.elevation' = topbank.elevation,
            'spill.elevation' = spill.elevation,
            'distance.to.bottom' = distance.to.bottom
        )
    ))
}

plot.transect <- function(transect.model, intervention=FALSE, output.dir=NULL){
    transect.coords = transect.model$transect.coords
    wp.coords = transect.model$wp.coords
    structure.coords = transect.model$structure.coords
    site.code <- transect.model$site.code
    #l.bank.index
    ### height and width in cm for sizing the image
    height <- (max(transect.coords[ , 2]) - min(transect.coords[ , 2])) * 100
    width <- (transect.coords[nrow(transect.coords), 1] -
              transect.coords[1, 1]) * 100
    ### scale the image to 1:500 horizontal and 1:100 vertical
    ### still need to work out the margins
    #print(width/500)
    #print(height/100)
    ### the title byline
    SH <- switch(as.character(intervention), 'FALSE'='',
                 'TRUE'='Post Intervention ')
    ### There's a +10 in here?
    if(!is.null(output.dir)){
        png(paste(output.dir, SH, site.code, '.png', sep=''),
            width=(width/500)+10, (height=height/100)+10, units='cm', res=72)}
    xlims <- c(transect.coords[1, 1], transect.coords[nrow(transect.coords), 1])
    ### Theres a -0.1 in here?
    ylims <- c(min(c(min(transect.coords[ , 2]), structure.coords[ , 2]))-0.1,
               max(transect.coords[ , 2]))
    ### land polygon units
    P.H <- matrix(c(-10000, -10000, -10000, transect.coords[1, 2]), ncol=2)
    P.T <- matrix(
        c(10000, 10000, transect.coords[nrow(transect.coords), 2], -10000),
        ncol=2)
    plot.new()
    plot.window(xlims, ylims)
    grid()
    title(main=paste('Top Bank Full', site.code, SH),
          xlab='Transverse Distance (m)', ylab='Elevation (m)')
    #lines(transect.coords, lwd=2, col=rgb(0.4,0.6,0.4))
    polygon(rbind(P.H, transect.coords, P.T),col=rgb(0.4,0.6,0.4, alpha=0.5))
#    lines(transect.coords[geometry['l.bank.index']:geometry['r.bank.index'], ],
#                          col='brown', lwd=2)
    lines(transect.coords, col='brown', lwd=2)
    polygon(wp.coords, col=rgb(0.53,0.8,0.98, alpha=0.5), border=NA)
    if(intervention){polygon(structure.coords, lwd=2,
                             col=rgb(0.98,0.8,0.73, alpha=0.5), border='brown')
    } else { polygon(structure.coords, lwd=2, col=rgb(0.53,0.8,0.98, alpha=0.5),
                     border=NA)
    }
    #mtext(paste(round(xsec.area), expression(m^2)), 4, col='blue', size=20)
    axis(1, at=c(0, transect.coords[nrow(transect.coords), 1]), col='light grey'
         )
    axis(2, col='light grey')
    if(!is.null(output.dir)){ dev.off() }
}

creek.model <- function(levels, read.func=read.qgis.csv,
                        input.dir='./input_csvs/'){
    ### This function operates on all sites along a creek returning a list I've
    ### set this up wrong: rather than taking a path to a directory full of CSVs
    ### with coordinates it should take a list of dataframes
    levels <- levels[order(levels[['distance.to.bottom']]), ]
    if(is.null(levels$fnames)){
        fnames <- paste(input.dir, levels$site.code, '.csv', sep='')
    } else { fnames <- levels$fnames }
    transects <- vector('list', nrow(levels))
    for(i in 1:nrow(levels)){
        #print(fnames[i])
        tryCatch(
            transects[[i]] <- transect.model(
                read.func(fnames[i]),
                levels[i, 'topbank.elevation'],
                levels[i, 'spill.elevation'],
                levels[i, 'thalweg.elevation'],
                levels[i, 'distance.to.bottom'],
                levels[i, 'site.code']
            ),
            error=function(cond){
                message(paste(
                    '\n\nsite', levels[i, 'site.code'], 'failed. Message:'
                ))
                message(cond)
                message('Check that you\'ve picked an appropriate CSV reader\n\n')
                }
        )
    }
    return(transects)
}

plot.creek.model <- function(creek.model, output.dir=NULL,
                             plot.device=png){
    if(is.null(output.dir)){
        output.dir <- paste('./x-sections_',
                            format(Sys.time(), "%Y-%m-%d-%H:%M"), '/')
        dir.create(output.dir)
        }
    for(transect in creek.model){
        plot.transect(transect, intervention=TRUE, output.dir=output.dir)
        plot.transect(transect, intervention=FALSE, output.dir=output.dir)
    }
}


model.from.transects <-
    function(transects, output.dir=NULL, catchment.name='unnamed catchment',
             source.ref='', plot.device=png){
        if(is.null(output.dir)){
            output.dir <- paste('./x-sections_',
                                format(Sys.time(), "%Y-%m-%d-%H%M"), '/', sep='')
            dir.create(output.dir)
        }
        for(transect in transects){
            plot.transect(transect, intervention=TRUE, output.dir=output.dir)
            plot.transect(transect, intervention=FALSE, output.dir=output.dir)
        }
        model <- extract.model.parameters(transects)
        write.csv(model, paste(output.dir, 'model_ouput.csv'))
        draw.sites.chart(model, catchment.name=catchment.name,
                         source.ref=source.ref, output.dir=output.dir)
        draw.levels.chart(model, catchment.name=catchment.name,
                          source.ref=source.ref, output.dir=output.dir)
        return(model)
    }

extract.model.parameters <- function(transects, sc.ordering=NULL){
    cnnnn <- c('site.code', names(transects[[1]]$parameters),
               names(transects[[1]]$data))
    site.code <- sapply(transects, '[[', 'site.code')
    model.parameters <- as.data.frame(as.matrix(numeric(0), ncol=length(cnnnn)),
                                      stringsAsFactors=FALSE, col.names=cnnnn)
    for(transect in transects){
        RR <- with(transect,
                    data.frame(
                        site.code=transect$site.code,
                        thalweg.elevation=parameters['thalweg.elevation'],
                        topbank.elevation=parameters['topbank.elevation'],
                        spill.elevation=parameters['spill.elevation'],
                        distance.to.bottom=parameters['distance.to.bottom'],
                        thalweg.elevation=parameters['thalweg.elevation'],
                        depth=data['depth'],
                        xsec.area=data['xsec.area'],
                        base.channel.width.distance=data['base.channel.width.distance'],
                        wp.length=data['wp.length'],
                        pi.depth=data['pi.depth'],
                        pi.xsec.area=data['pi.xsec.area'],
                        structure.xsec.area=data['structure.xsec.area'],
                        structure.width.distance=data['structure.width.distance'],
                        pi.wp.length=data['pi.wp.length'],
                        row.names=NULL,
                        stringsAsFactors=FALSE)
                    )
        model.parameters <- rbind(model.parameters, RR)
    }
    return(model.parameters)
}

### should define a named list of formulas as expressions then use
### eval(expr, envir=data.frame(xsec.area=shr$sxec.area, wp.length=shr$wp.length
model.calculation <- function(parameters, gradient=NULL, pi.gradient=NULL,
                              roughness=NULL, pi.roughness=NULL){
    if(!is.null(gradient)){ parameters$gradient <- gradient }
    if(!is.null(pi.gradient)){ parameters$pi.gradient <- pi.gradient }
    if(!is.null(roughness)){ parameters$roughness <- roughness }
    if(!is.null(pi.roughness)){ parameters$pi.roughness <- pi.roughness }
    parameters$hydraulic.radius <- parameters$xsec.area / parameters$wp.length
    parameters$pi.hydraulic.radius <-
        parameters$pi.xsec.area / parameters$pi.wp.length
    parameters$velocity <-
        with(parameters, ((hydraulic.radius^(2/3))*(gradient^(1/2)))/roughness)
    parameters$pi.velocity <-
        with(parameters, ((pi.hydraulic.radius^(2/3))*(pi.gradient^(1/2)))
             /pi.roughness)
    parameters$discharge <- with(parameters, velocity*xsec.area)
    parameters$pi.discharge <- with(parameters, pi.velocity*pi.xsec.area)
    parameters$traction <- with(parameters, 9806 * depth * gradient)
    parameters$pi.traction <- with(parameters, 9806 * pi.depth * pi.gradient)
    parameters$stream.power <-
        with(parameters, 9806 * depth * discharge * gradient)
    parameters$pi.stream.power <-
        with(parameters, 9806 * pi.depth * pi.discharge * pi.gradient)
    parameters$unit.stream.power <- with(parameters, stream.power
                                         / base.channel.width.distance)
    parameters$pi.unit.stream.power <- with(parameters, pi.stream.power
                                            / base.channel.width.distance)
    parameters$froude.number <- with(parameters, velocity / ((9.8 * depth)^0.5))
    parameters$pi.froude.number <- with(parameters, pi.velocity /
                                                    ((9.8 * pi.depth)^0.5))
    return(parameters)
}

calculate.gradient <- function(shr, pi=FALSE, rowname.var='site.code'){
    ### Uses rownames and vectors specifying US and DS sites to calculate
    ### gradients
    if(is.character(rowname.var)){
        rownames(shr) <- shr[[rowname.var]]}
    out <- numeric()
    if(pi){
        height <- 'spill.elevation'
    } else { height <- 'thalweg.elevation' }
    for( i in 1:nrow(shr) ){
        us.height <- shr[shr[i, 'us.step.for.grad'], height]
        ds.height <- shr[shr[i, 'ds.step.for.grad'], height]
        run <- abs(
            shr[shr[i, 'us.step.for.grad'], 'distance.to.bottom'] -
            shr[shr[i, 'ds.step.for.grad'], 'distance.to.bottom']
        )
        grad <- (us.height - ds.height) / run
        out <- c(out, grad)
    }
    if(any(is.na(out))){
        warning(paste('Gradients were not calculated for the',
                      'following sites:',
                      paste(rownames(shr)[is.na(out)], collapse=', '),
                      'Check that variables us.step.for.grad and',
                      'ds.step.for.grad are specified and refer to',
                      'other rows of the table.'
                      ))
    }
    return(out)
}

MCCC.barplot <- function(df, arg.names=NULL, main='', xlab='', ylab='',
                         fname=NULL, legend.location='topright', ...){
  colours=c(
    MCCC.green = '#395624',
    MCCC.blue = '#5876b0',
    MCCC.brown = '#6b2223',
    MCCC.teal = '#1f6e6e',
    MCCC.purple = '#6647a0',
    MCCC.grey = '#4e4e4e'
  )
  if(!is.null(fname)){ svg(fname, height=4, width=10) }
  if(ncol(df)>1){ colours <- colours[1:ncol(df)]
  } else { colours <- colours[1] }
  plot.new()
  barplot(height=t(as.matrix(df)), col=colours, beside=T,
          names.arg=arg.names, space=c(0.2,1), xlab=xlab,
          main=main, border=NA, ...)
  title(ylab=ylab, line = 2.5)
  legend(legend.location, legend=c('pre-intervention', 'post-intervention'), fill=colours[1:2], bty='n', border=NA)
  if(!is.null(fname)){ dev.off() }
}

## MCCC.barplot <- function(df, arg.names=NULL, fname=NULL, ylab=NULL, ...){
##     colours=c(
##         MCCC.green = '#395624',
##         MCCC.blue = '#5876b0',
##         MCCC.brown = '#6b2223',
##         MCCC.teal = '#1f6e6e',
##         MCCC.purple = '#6647a0',
##         MCCC.grey = '#4e4e4e'
##     )
##     print(paste(...))
##     if(!is.null(fname)){ svg(fname, height=4, width=10) }
##     if(ncol(df)>1){ colours <- colours[1:ncol(df)]
##     } else { colours <- colours[1] }
##     plot.new()
##     barplot(height=t(as.matrix(df)), col=colours, beside=TRUE,
##             names.arg=arg.names, border=NA, space=c(0.2,1), ...)
##     title(ylab=ylab, line =-5)
##     legend('topleft', legend=c('pre-intervention', 'post-intervention'), fill=colours[1:2], bty='n', border=NA)
##     if(!is.null(fname)){ dev.off() }
## }

hydraulics.output <- function(hydraulics.data, width=10, height=4, ...){
  output.dir <- paste('Hydraulics_',
                      format(Sys.time(), "%Y-%m-%d-%H-%M"), '/', sep='')
  dir.create(output.dir)
  write.csv(hydraulics.data, paste(output.dir, 'hydraulics_output.csv', sep=''))
  ### XSEC
  MCCC.barplot(hydraulics.data[ ,c('xsec.area', 'pi.xsec.area')], hydraulics.data$site.code, 'Cross Sectional Area', ylab=expression(paste("cross sectional area m"^"2", "")), xlab='Site', fname=paste(output.dir, 'Cross Sectional Area.svg', sep=''), ...)
  
  ### VELOCITY
  MCCC.barplot(hydraulics.data[ , c('velocity', 'pi.velocity')],
               hydraulics.data$site.code,
               'Stream Velocity',
               ylab=expression(paste("Stream Velocity ms"^"-1", "")),
               xlab='Site',
               fname=paste(output.dir, 'Stream Velocity.svg', sep=''),
               ...
  )
  
  ### Discharge
  MCCC.barplot(hydraulics.data[ ,c('discharge', 'pi.discharge')], hydraulics.data$site.code, 'Discharge', ylab=expression(paste("Discharge m"^"3", "s"^"-1", "")), xlab='Site', fname=paste(output.dir, 'Discharge.svg', sep=''), ...)
  
  ### Shear Stress
  MCCC.barplot(hydraulics.data[ ,c('traction', 'pi.traction')], hydraulics.data$site.code, 'Shear Stress', ylab=expression(paste("Shear Stress N")), xlab='Site', fname=paste(output.dir, 'Shear Stress.svg', sep=''), ...)
  
  ### Stream Power
  MCCC.barplot(hydraulics.data[ ,c('stream.power', 'pi.stream.power')], hydraulics.data$site.code, 'Stream Power', ylab=expression(paste("Stream Power W")), xlab='Site', fname=paste(output.dir, 'Stream Power.svg', sep=''), ...)
  
  ### Unit Stream Power
  MCCC.barplot(hydraulics.data[ ,c('unit.stream.power', 'pi.unit.stream.power')], hydraulics.data$site.code, 'Unit Stream Power', ylab=expression(paste("Unit Stream Power Wm"^"-2", "")), xlab='Site', fname=paste(output.dir, 'Unit Stream Power.svg', sep=''), ...)
  
  ### Froude Number
  MCCC.barplot(hydraulics.data[ ,c('froude.number', 'pi.froude.number')], hydraulics.data$site.code, 'Froude Number', ylab=expression(paste("Froude Number")), xlab='Site', fname=paste(output.dir, 'Froude Number.svg', sep=''), ...)
  
  ### Gradient
  MCCC.barplot(hydraulics.data[ ,c('gradient', 'pi.gradient')], hydraulics.data$site.code, 'Gradient', ylab=expression(paste("Gradient mm"^"-1")), xlab='Site', fname=paste(output.dir, 'Gradient.svg', sep=''), ...)
}


